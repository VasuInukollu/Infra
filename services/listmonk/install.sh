#!/usr/bin/env bash
set -euo pipefail

service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this installer as root." >&2
    exit 1
fi

for command_name in curl docker openssl psql runuser systemctl caddy; do
    command -v "${command_name}" >/dev/null || {
        echo "Required command is missing: ${command_name}" >&2
        exit 1
    }
done

if ss -lnt "sport = :9000" | grep -q LISTEN && \
    ! docker inspect listmonk >/dev/null 2>&1; then
    echo "Port 9000 is already used by something other than Listmonk." >&2
    exit 1
fi

deployment_dir="/var/snap/docker/common/listmonk"
environment_file="${deployment_dir}/listmonk.env"
install -d -m 0700 "${deployment_dir}"
install -d -o root -g root -m 0700 /etc/inukollu/listmonk

credentials_created="false"
if [[ ! -f "${environment_file}" ]]; then
    database_password="$(openssl rand -base64 36 | tr -d '\n')"
    admin_password="$(openssl rand -base64 24 | tr -d '\n')"

    runuser -u postgres -- psql -X --set=ON_ERROR_STOP=1 \
        --set=listmonk_password="${database_password}" <<'SQL'
SELECT format('CREATE ROLE listmonk LOGIN PASSWORD %L', :'listmonk_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'listmonk') \gexec
SELECT format('ALTER ROLE listmonk WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD %L', :'listmonk_password') \gexec
SELECT 'CREATE DATABASE listmonk OWNER listmonk'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'listmonk') \gexec
ALTER DATABASE listmonk OWNER TO listmonk;
SQL

    umask 077
    env_file="${environment_file}.tmp"
    printf '%s\n' \
        'LISTMONK_app__address=127.0.0.1:9000' \
        'LISTMONK_db__host=127.0.0.1' \
        'LISTMONK_db__port=5432' \
        'LISTMONK_db__user=listmonk' \
        "LISTMONK_db__password=${database_password}" \
        'LISTMONK_db__database=listmonk' \
        'LISTMONK_db__ssl_mode=disable' \
        'LISTMONK_db__max_open=10' \
        'LISTMONK_db__max_idle=5' \
        'LISTMONK_db__max_lifetime=300s' \
        'LISTMONK_ADMIN_USER=admin' \
        "LISTMONK_ADMIN_PASSWORD=${admin_password}" \
        'TZ=Asia/Kolkata' >"${env_file}"
    install -o root -g root -m 0600 "${env_file}" "${environment_file}"
    rm -f -- "${env_file}"

    credentials_file="/root/listmonk-initial-admin.txt.tmp"
    printf 'URL: https://lists.inukollu.in\nUsername: admin\nPassword: %s\n' \
        "${admin_password}" >"${credentials_file}"
    install -o root -g root -m 0600 "${credentials_file}" /root/listmonk-initial-admin.txt
    rm -f -- "${credentials_file}"
    credentials_created="true"
fi

# Keep a separate root-only safekeeping copy outside Docker's runtime directory.
set -a
# shellcheck disable=SC1090
source "${environment_file}"
set +a
password_backup="/etc/inukollu/listmonk/db-password.tmp"
printf '%s\n' "${LISTMONK_db__password}" >"${password_backup}"
install -o root -g root -m 0600 "${password_backup}" /etc/inukollu/listmonk/db-password
rm -f -- "${password_backup}"

install -o root -g root -m 0600 "${service_dir}/compose.yaml" "${deployment_dir}/compose.yaml"
docker compose --project-directory "${deployment_dir}" -f "${deployment_dir}/compose.yaml" config --quiet
docker compose --project-directory "${deployment_dir}" -f "${deployment_dir}/compose.yaml" pull
docker compose --project-directory "${deployment_dir}" -f "${deployment_dir}/compose.yaml" up -d

for attempt in {1..30}; do
    if curl --fail --silent --output /dev/null http://127.0.0.1:9000/; then
        break
    fi
    if [[ "${attempt}" -eq 30 ]]; then
        docker logs --tail 50 listmonk
        echo "Listmonk did not become healthy; Caddy was not changed." >&2
        exit 1
    fi
    sleep 1
done

caddy_target="/etc/caddy/sites/listmonk.caddy"
formatted_caddy="$(mktemp)"
trap 'rm -f -- "${formatted_caddy}"' EXIT
install -m 0644 "${service_dir}/listmonk.caddy" "${formatted_caddy}"
caddy fmt --overwrite "${formatted_caddy}"
if [[ -e "${caddy_target}" ]] && ! cmp --silent "${formatted_caddy}" "${caddy_target}"; then
    echo "Refusing to overwrite differing ${caddy_target}." >&2
    exit 1
fi
install -o root -g caddy -m 0644 "${formatted_caddy}" "${caddy_target}"
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy

curl --fail --silent --show-error --resolve lists.inukollu.in:443:127.0.0.1 \
    --retry 15 --retry-delay 2 --output /dev/null https://lists.inukollu.in/

echo "Listmonk is running at https://lists.inukollu.in"
if [[ "${credentials_created}" == "true" ]]; then
    echo "Initial credentials: /root/listmonk-initial-admin.txt"
fi

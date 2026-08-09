#!/usr/bin/env bash
set -euo pipefail

service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
deployment_dir="/var/snap/docker/common/geoip-api"
compose_file="${deployment_dir}/compose.yaml"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this installer as root." >&2
    exit 1
fi

for command_name in curl docker flock ss systemctl; do
    command -v "${command_name}" >/dev/null || {
        echo "Required command is missing: ${command_name}" >&2
        exit 1
    }
done

if ss -lnt "sport = :8082" | grep -q LISTEN && \
    ! docker inspect geoip-api >/dev/null 2>&1; then
    echo "Port 8082 is already used by something other than geoip-api." >&2
    exit 1
fi

install -d -o root -g root -m 0755 "${deployment_dir}"
install -o root -g root -m 0644 "${service_dir}/compose.yaml" "${compose_file}"
install -o root -g root -m 0755 "${service_dir}/update.sh" \
    /usr/local/sbin/geoip-api-update
install -o root -g root -m 0644 "${service_dir}/geoip-api-update.service" \
    /etc/systemd/system/geoip-api-update.service
install -o root -g root -m 0644 "${service_dir}/geoip-api-update.timer" \
    /etc/systemd/system/geoip-api-update.timer

docker compose --project-directory "${deployment_dir}" \
    -f "${compose_file}" config --quiet
/usr/local/sbin/geoip-api-update

if ss -H -lnt "sport = :8082" | grep -Evq '127\.0\.0\.1:8082'; then
    echo "geoip-api is unexpectedly listening beyond loopback." >&2
    exit 1
fi

systemctl daemon-reload
systemctl enable --now geoip-api-update.timer

echo "geoip-api is running at http://127.0.0.1:8082"

#!/usr/bin/env bash
set -euo pipefail

deployment_dir="/var/snap/docker/common/geoip-api"
compose_file="${deployment_dir}/compose.yaml"
image="observabilitystack/geoip-api:latest"

exec 9>/run/lock/geoip-api-update.lock
flock --nonblock 9 || {
    echo "Another geoip-api update is already running."
    exit 0
}

previous_image_id=""
if docker inspect geoip-api >/dev/null 2>&1; then
    previous_image_id="$(docker inspect geoip-api --format '{{.Image}}')"
fi

docker compose --project-directory "${deployment_dir}" \
    -f "${compose_file}" pull app
docker compose --project-directory "${deployment_dir}" \
    -f "${compose_file}" up -d --no-deps app

healthy="false"
for attempt in {1..30}; do
    if curl --fail --silent --output /dev/null \
        http://127.0.0.1:8082/8.8.8.8; then
        healthy="true"
        break
    fi
    sleep 1
done

if [[ "${healthy}" == "true" ]]; then
    docker inspect geoip-api --format \
        'geoip-api update healthy: image={{.Config.Image}} id={{.Image}}'
    exit 0
fi

docker logs --tail 50 geoip-api >&2 || true
if [[ -z "${previous_image_id}" ]]; then
    echo "geoip-api failed its lookup check and no rollback image exists." >&2
    exit 1
fi

echo "Lookup check failed; rolling back to ${previous_image_id}." >&2
docker image tag "${previous_image_id}" "${image}"
docker compose --project-directory "${deployment_dir}" \
    -f "${compose_file}" up -d --no-deps --force-recreate app

for attempt in {1..30}; do
    if curl --fail --silent --output /dev/null \
        http://127.0.0.1:8082/8.8.8.8; then
        echo "geoip-api rollback is healthy." >&2
        exit 1
    fi
    sleep 1
done

docker logs --tail 50 geoip-api >&2 || true
echo "geoip-api update and rollback both failed." >&2
exit 1

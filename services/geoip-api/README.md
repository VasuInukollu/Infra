# GeoIP API deployment

This service runs the third-party `observabilitystack/geoip-api` image on the
NUC. It provides JSON GeoIP lookups to applications running on the same host.

## Runtime layout

- Compose project: `/var/snap/docker/common/geoip-api/compose.yaml`
- Container: `geoip-api`
- Image: `observabilitystack/geoip-api:latest`, refreshed automatically weekly
- Listener: `127.0.0.1:8082`
- Persistence: none; the pinned weekly image contains the GeoLite2 databases
- Authentication: none; isolation is enforced by the loopback-only listener

Port 8082 is used because ports 8080 and 8081 are already allocated on the NUC.
There is deliberately no DNS name or Caddy route. Processes on other hosts,
including other Tailscale nodes, cannot connect directly.

The image's shell entrypoint does not start when all capabilities are dropped or
Docker's `no-new-privileges` flag is set. The container instead uses a read-only
root filesystem, resource limits, and loopback-only network exposure.

## API

Look up one address:

```bash
curl --fail --silent http://127.0.0.1:8082/8.8.8.8
```

The API also accepts up to 100 addresses in a JSON array sent to `/`. See the
upstream image documentation for its response fields and header-based API.

## Deploy and verify

Copy this directory to the NUC and run `sudo ./install.sh`. The installer only
starts or updates the `geoip-api` Compose service; it does not change Caddy or
restart unrelated containers.

```bash
docker ps --filter name=^/geoip-api$
curl --fail --silent http://127.0.0.1:8082/8.8.8.8
ss -lnt 'sport = :8082'
```

## Updates and rollback

The upstream project publishes a fresh image and bundled database weekly and
explicitly recommends `latest` for current GeoIP data. The
`geoip-api-update.timer` systemd timer pulls it every Sunday after 03:30 with up
to four hours of randomized delay. The updater recreates only this Compose
service, verifies a real lookup, and restores the previously running image if
the check fails. A missed run executes after the NUC next boots.

Inspect automation with:

```bash
systemctl status geoip-api-update.timer
systemctl list-timers geoip-api-update.timer
journalctl -u geoip-api-update.service
```

No data restore is needed because the service has no persistent state.

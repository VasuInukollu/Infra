# Listmonk deployment

This deployment runs Listmonk in Docker on the NUC and uses the NUC's existing
PostgreSQL server. It deliberately does not deploy another PostgreSQL instance.

## Runtime layout

- Compose project: `/var/snap/docker/common/listmonk/compose.yaml`
- Runtime environment: `/var/snap/docker/common/listmonk/listmonk.env` (`0600`)
- Database password backup: `/etc/inukollu/listmonk/db-password` (`0600`)
- Uploads: Docker volume `listmonk-uploads`
- Container: `listmonk`
- Listener: `127.0.0.1:9000`
- Database/role: `listmonk` / `listmonk`
- Caddy site: `/etc/caddy/sites/listmonk.caddy`
- URL: `https://lists.inukollu.in`
- Initial credentials: `/root/listmonk-initial-admin.txt` (`0600`)

The initial credential file should be read once, placed in the operator's
password manager, and removed from the host after login is verified.

The Compose and runtime environment files live under `/var/snap/docker/common`
because the NUC's Docker installation is Snap-confined. The `/etc` password file
is a separate safekeeping copy; it is not mounted or read by the container.

## Safety properties

- No PostgreSQL configuration or listener changes.
- No access to the existing `privatenumber` database.
- No externally published application port.
- Host networking is used because PostgreSQL only listens on host loopback. The
  application itself is explicitly bound to `127.0.0.1:9000`.
- Caddy configuration is additive and validated before graceful reload.
- The Listmonk container version is pinned in `compose.yaml`.

## Deploy

Copy this directory to the NUC and run `sudo ./install.sh`. The script is
idempotent and refuses to overwrite an existing Caddy site file with different
content.

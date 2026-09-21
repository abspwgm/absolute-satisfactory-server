# absolute-satisfactory-server

A containerized dedicated server for **Satisfactory**, built from
[absolute-server-template](https://github.com/abspwgm/absolute-server-template)
and conforming to the
Absolute engineering standard.

**New to this? Start here: [docs/INSTALL.md](docs/INSTALL.md)** — written for
someone who has never used Docker, a terminal or a router's settings page.

## Quick start

```yaml
services:
  satisfactory:
    image: ghcr.io/abspwgm/absolute-satisfactory-server:latest
    container_name: satisfactory-server
    restart: unless-stopped
    stop_grace_period: 180s
    ports:
      - "7777:7777/udp"
      - "7777:7777/tcp"
      - "127.0.0.1:8888:8888/tcp"
    volumes:
      - satisfactory-server:/opt/satisfactory/server
      - satisfactory-config:/config

volumes:
  satisfactory-server:
  satisfactory-config:
```

```sh
docker compose up -d
```

The first start downloads the server and generates a world, which takes a
while. `docker ps` shows `(healthy)` when players can join.

## Ports

| Port | Protocol | Purpose | Forward on your router? |
|---|---|---|---|
| 7777 | UDP | Game traffic | Yes |
| 7777 | TCP | Game messaging | Yes |
| 8888 | TCP | Management API | **No — keep private** |

## Settings

| Variable | Default | What it does |
|---|---|---|
| `SERVER_PORT` | `7777` | Game port |
| `UPDATE_ON_START` | `true` | Take the newest game build when the container starts |
| `BACKUPS_ENABLED` | `true` | Hourly world backups |
| `BACKUPS_MAX_COUNT` | `10` | How many backups to keep |
| `SERVER_EXTRA_ARGS` | (empty) | Extra arguments passed to the server |
| `TZ` | `Etc/UTC` | Timezone for logs and schedules |

## Status

**Not yet released.** The container layer is new — this is the first game built
from the template — and two values in
[`manifest.env`](manifest.env) are marked UNVERIFIED until the first green
end-to-end run confirms them: the server's process name and the log line that
means "players can join".

Open exceptions are recorded with dates in
[`.absolute/policy.yml`](.absolute/policy.yml): no snapshot/hold/rollback yet,
no scheduled build watch, and no published image. The remaining work is in
[CHECKLIST.md](CHECKLIST.md).

## Licence

Apache-2.0. See [LICENSE](LICENSE).

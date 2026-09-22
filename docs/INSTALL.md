# Run a Satisfactory server

Written for someone who has never used Docker, a terminal, or their router's
settings page. Every command can be copied as it is. After each step there is a
line telling you what it should look like when it worked.

You need a computer that stays on — the server is only up while that computer
is. 16 GB of memory and about 20 GB of free disk is a comfortable starting
point.

---

## 1. Install Docker

Go to **https://docs.docker.com/get-started/get-docker/** and install Docker
Desktop for your operating system. Accept the defaults.

Open a terminal (**PowerShell** on Windows, **Terminal** on macOS or Linux) and
type:

```sh
docker --version
```

**It worked if** you see something like `Docker version 27.3.1`. If you see
"command not found", Docker did not finish installing — restart the computer
and try again.

---

## 2. Make a folder for the server

```sh
mkdir satisfactory-server
cd satisfactory-server
```

**It worked if** the terminal prompt now mentions `satisfactory-server`.

---

## 3. Create the configuration file

Create a file called `docker-compose.yml` in that folder, and paste this in:

```yaml
services:
  satisfactory:
    image: abspwgm/absolute-satisfactory-server:latest
    container_name: satisfactory-server
    restart: unless-stopped
    stop_grace_period: 180s
    ports:
      - "7777:7777/udp"
      - "7777:7777/tcp"
      - "127.0.0.1:8888:8888/tcp"
    environment:
      - TZ=Etc/UTC
    volumes:
      - satisfactory-server:/opt/satisfactory/server
      - satisfactory-config:/config

volumes:
  satisfactory-server:
  satisfactory-config:
```

**It worked if** the file is saved in the same folder you are in.

---

## 4. Start it

```sh
docker compose up -d
```

The first start downloads the game server — several gigabytes — and then
generates your world. **This takes a long time**, often twenty minutes or more,
and it looks like nothing is happening. That is normal.

Watch it with:

```sh
docker compose logs -f
```

**It worked if** the log stops scrolling and settles. Press `Ctrl+C` to stop
watching — that stops the watching, not the server.

Check it is healthy:

```sh
docker ps
```

**It worked if** the line for `satisfactory-server` says `(healthy)`. If it
says `(health: starting)`, the world is still generating; wait and look again.

---

## 5. Let your friends in

Your friends are on the internet and your server is on your home network, so
your router has to be told to pass the game through. This is called **port
forwarding**.

| Port | Protocol | What it is | Forward it? |
|---|---|---|---|
| 7777 | UDP | The game itself | **Yes** |
| 7777 | TCP | Game messaging | **Yes** |
| 8888 | TCP | Server management API | **No — keep private** |

Forward **only** 7777. The compose file above already binds 8888 so that it is
reachable from the computer running the server and nowhere else.

Follow the shared guide: **[Port forwarding](https://github.com/abspwgm/absolute-game-servers/blob/main/docs/port-forwarding.md)**.
It covers finding your router's page, reserving an address so the rule does not
break, testing it, and what to do if your internet provider uses CGNAT and
forwarding cannot work at all.

---

## 6. Join

In Satisfactory: **Server Manager → Add Server**, and enter your public IP
address with port `7777`. The first person to connect claims the server and
sets its admin password.

---

## Everyday commands

| What you want | Command |
|---|---|
| Stop the server | `docker compose stop` |
| Start it again | `docker compose start` |
| Update to the newest image | `docker compose pull && docker compose up -d` |
| See what it is doing | `docker compose logs -f` |
| Where the saves live | inside the `satisfactory-config` volume, under `saved` |

The server saves when it shuts down, so always use `docker compose stop` rather
than closing the terminal or powering the machine off.

---

## When something is wrong

| What you see | What it means | What to do |
|---|---|---|
| `docker: command not found` | Docker is not installed or not started | Reinstall, then restart the computer |
| `(health: starting)` for over an hour | The world is still generating, or the download stalled | `docker compose logs --tail 50` and look for repeated errors |
| `(unhealthy)` | The game is not running, or its port is not bound | `docker compose logs --tail 50`; if it repeats, `docker compose restart` |
| Friends cannot connect, but you can | Port forwarding is not working | Work through the port forwarding guide again |
| `port is already allocated` | Something else on the machine uses 7777 | Stop it, or change the left-hand `7777` in the compose file |

Still stuck? Open an issue at
**https://github.com/abspwgm/absolute-satisfactory-server/issues** with the last
50 lines of `docker compose logs`. Do not paste your IP address or your admin
password.

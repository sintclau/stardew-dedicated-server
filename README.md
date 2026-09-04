# Stardew Valley Dedicated Server (headless, Docker) — 1.6

An always-on, headless **Stardew Valley 1.6** multiplayer server in Docker, built to run
on **your own** game files — including the **GOG** Linux build (no Steam account required).

Unlike [JunimoServer](https://github.com/stardew-valley-dedicated-server/server) (excellent,
but hard-requires a Steam login to download and authenticate), this image is a small DIY
container that:

- installs [SMAPI](https://smapi.io) at startup against your mounted game files,
- runs the [StardewUnattendedServer](https://github.com/theghost99/StardewUnattendedServer)
  mod to keep the host farmer alive (auto-sleep, festivals, community center…),
- renders headlessly with **Xvfb + Mesa software OpenGL** (no GPU needed),
- and lets friends join via **direct IP / "Join LAN Game"** on UDP `24642`.

> ⚠️ **You must own the game.** This repo ships **no** game files. Supply your own
> legally-obtained **Linux** build (GOG offline installer or a Steam Linux install).

---

## How it works (and its limits)

Stardew has no official dedicated server. The trick is to run the *full game* headless
with a mod that automates the host player. Key consequences:

- **You need a pre-made multiplayer host save.** The unattended mod hosts an existing
  save; it does not create a farm from scratch. Create the farm on your PC first
  (with cabins), then upload the save.
- **You need an auto-loader.** The unattended mod only activates *after* a host save is
  loaded, so we pair it with **Auto Load Game** ([Nexus #2509](https://www.nexusmods.com/stardewvalley/mods/2509))
  to load the save at boot. Nexus mods can't be auto-downloaded — you drop it into `./mods`.
- **Connections are direct-IP (LAN mode).** On a GOG headless box the Galaxy invite-code
  path won't work (no Galaxy login), but the game's LAN server on UDP `24642` runs fine.
  Friends use **Co-op → Join LAN Game → `<your server IP>`**.

---

## Prerequisites

- A Linux host with **Docker** + **Docker Compose v2**.
- Your **Linux** Stardew Valley game files (GOG `.sh` installer, or a Steam Linux install).
- **Auto Load Game** mod from Nexus (#2509).
- A **multiplayer host save** you created on your own machine.

---

## Setup

### 1. Get the code
```bash
git clone https://github.com/<you>/stardew-dedicated-server.git
cd stardew-dedicated-server
```

### 2. Extract your game into `./game`

**GOG (recommended):** download the **Linux** offline installer from your GOG library
(*Download offline backup game installers → Linux* → a single `stardew_valley.sh`), then:
```bash
scripts/extract-game.sh /path/to/stardew_valley.sh
# -> populates ./game with the Linux build (Stardew Valley.dll, Content/, lib*.so, ...)
```

**Steam:** copy your Linux `Stardew Valley/` install directory contents into `./game`.

### 3. Add the auto-loader
Download **Auto Load Game** (Nexus #2509), unzip, and place the mod folder into `./mods`:
```
mods/
  AutoLoadGame/
    manifest.json
    ...
```

### 4. Add your host save
Create a co-op farm on your PC (New → Co-op → add cabins → play a day → sleep to save),
then copy the save folder into `./saves`:
```
saves/
  Farmhands_123456789/
    Farmhands_123456789
    SaveGameInfo
    ...
```
Save locations on your PC: `~/.config/StardewValley/Saves` (Linux/macOS) or
`%APPDATA%\StardewValley\Saves` (Windows).

### 5. (Optional) tune the server
```bash
cp config/unattended-config.example.json config/unattended-config.json
# edit auto-sleep time, profit margin, festivals on/off, etc.
```

### 6. Build & run
```bash
docker compose up -d --build
docker compose logs -f
```
First boot installs SMAPI, loads your save, and starts hosting. Watch for
`Server Mode On!` in the logs.

---

## Connecting

The server hosts on **UDP `24642`**. In-game: **Co-op → Join LAN Game → type the IP**.

### Option A — Tailscale (recommended, zero public ports)
Install Tailscale on the **host**, then bind the port to the tailnet IP in
`docker-compose.yml`:
```yaml
    ports:
      - "100.x.y.z:24642:24642/udp"   # your host's Tailscale IP
```
Friends install Tailscale, you share the machine/tailnet, and they join
`100.x.y.z` via "Join LAN Game". Nothing is exposed to the internet.

### Option B — Public
Leave the port unbound (`"24642:24642/udp"`) and open it on the host firewall.
Optionally add a **DNS-only (grey-cloud)** `A` record like `stardew.example.com`
→ the host's public IP so friends can type a hostname instead of an IP.

> **Cloudflare Tunnel does _not_ work for the game.** The Tunnel proxies HTTP/TCP, not
> arbitrary inbound UDP to anonymous clients — and Stardew multiplayer is UDP. A plain
> DNS record (grey cloud) is fine; the Tunnel is not.

> **Docker + ufw:** publishing a port inserts a DNAT rule that bypasses `ufw`. That's the
> intended behavior here (the port is meant to be reachable). To keep it private, prefer
> Option A (bind to the Tailscale IP).

---

## Operations

```bash
docker compose logs -f            # watch server / SMAPI output
docker compose restart            # restart the server
docker compose down               # stop
```

- **Saves** persist in `./saves` (mounted into the game's Saves dir). Back this up.
- **SMAPI + mods** are (re)synced into `./game/Mods` on every start.
- Update SMAPI by bumping `SMAPI_VERSION` in `docker-compose.yml` and rebuilding.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `No Stardew Valley Linux build found` | `./game` is empty or has the Windows build. Re-run `scripts/extract-game.sh` with the **Linux** installer. |
| Stuck at the title screen | Auto Load Game missing from `./mods`, or no host save in `./saves`. |
| `Server Mode On!` never appears | The loaded save isn't a **multiplayer host** save (must have cabins / be created as Co-op). |
| Friends can't connect | Port `24642/udp` not reachable (firewall / wrong IP). Test with Tailscale first. |
| GL / display errors in logs | Usually a missing lib — add the package to the Dockerfile `apt-get` list and rebuild. |
| High idle CPU | Expected: the game ticks ~60fps even headless. `cpus`/`mem_limit` cap it in compose. |

---

## Credits

- [SMAPI](https://github.com/Pathoschild/SMAPI) — Pathoschild
- [StardewUnattendedServer](https://github.com/theghost99/StardewUnattendedServer) — theghost99
- [Auto Load Game](https://www.nexusmods.com/stardewvalley/mods/2509)
- Inspiration: [JunimoServer](https://github.com/stardew-valley-dedicated-server/server)

## License

MIT — see [LICENSE](LICENSE). Does not include or distribute Stardew Valley.

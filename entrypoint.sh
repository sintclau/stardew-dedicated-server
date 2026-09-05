#!/usr/bin/env bash
# Boot sequence: install SMAPI (once) -> sync mods -> start Xvfb -> run SMAPI headless.
# Auto Load Game (a mod you supply in ./mods) loads your host save, which flips the
# unattended-server mod into "Server Mode On" and starts hosting for co-op.
set -euo pipefail

GAME_DIR="${GAME_DIR:-/data/game}"
SCREEN_RES="${SCREEN_RES:-1280x720x24}"

# ── 0. Sanity: is a Linux game build actually mounted? ──────────────────────────
if [ ! -e "${GAME_DIR}/Stardew Valley.dll" ] && [ ! -e "${GAME_DIR}/StardewValley.dll" ]; then
  echo "!! No Stardew Valley Linux build found at ${GAME_DIR}"
  echo "   Extract your GOG/Steam *Linux* build there (see scripts/extract-game.sh)."
  echo "   Expected files: 'Stardew Valley.dll', 'StardewValley' launcher, Content/, lib*.so"
  exit 1
fi

# ── 1. Install SMAPI into the game dir (idempotent) ─────────────────────────────
# Creates the StardewModdingAPI launcher + a Mods/ folder with SMAPI's bundled mods.
if [ ! -x "${GAME_DIR}/StardewModdingAPI" ]; then
  echo ">> Installing SMAPI into ${GAME_DIR} ..."
  # The installer zip ships a SMAPI.Installer for EACH OS (linux/macOS/windows), all
  # named the same — pick the Linux one explicitly, else we'd try to exec a Mach-O/PE.
  INSTALLER_BIN="$(find /opt/smapi-installer -type f -ipath '*/linux/*' -name 'SMAPI.Installer' | head -n1)"
  [ -z "${INSTALLER_BIN}" ] && INSTALLER_BIN="$(find /opt/smapi-installer -type f -name 'SMAPI.Installer' | head -n1)"
  if [ -z "${INSTALLER_BIN}" ]; then
    echo "!! Could not find SMAPI.Installer under /opt/smapi-installer"; exit 1
  fi
  ( cd "$(dirname "${INSTALLER_BIN}")" \
      && chmod +x ./SMAPI.Installer \
      && ./SMAPI.Installer --install --game-path "${GAME_DIR}" --no-prompt )
else
  echo ">> SMAPI already installed, skipping."
fi

# ── 2. Sync mods: baked unattended-server mod + your extra mods from /data/mods ──
mkdir -p "${GAME_DIR}/Mods"
cp -r /opt/baked-mods/. "${GAME_DIR}/Mods/" 2>/dev/null || true
if [ -d /data/mods ] && [ -n "$(ls -A /data/mods 2>/dev/null)" ]; then
  echo ">> Installing user mods from /data/mods ..."
  cp -r /data/mods/. "${GAME_DIR}/Mods/" 2>/dev/null || true
fi

# ── 3. Optional: overlay a custom unattended-server config.json ─────────────────
if [ -f /data/config/unattended-config.json ]; then
  echo ">> Applying custom unattended-server config ..."
  while IFS= read -r cfg; do
    cp /data/config/unattended-config.json "${cfg}"
  done < <(find "${GAME_DIR}/Mods" -maxdepth 2 -iname config.json -ipath '*Unattended*')
fi

# ── 4. Virtual display (software GL) + SMAPI, headless ──────────────────────────
mkdir -p "${XDG_CONFIG_HOME}"
echo ">> Starting Xvfb on ${DISPLAY} (${SCREEN_RES}) ..."
Xvfb "${DISPLAY}" -screen 0 "${SCREEN_RES}" -nolisten tcp &
XVFB_PID=$!

# Wait for X to accept connections before launching the game.
for _ in $(seq 1 40); do
  xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1 && break
  sleep 0.25
done

# Minimal window manager so the game window is positioned/sized correctly. Without one,
# the game opens off-center and the rest of the virtual screen stays black.
echo ">> Starting openbox window manager ..."
openbox &

# Once the game window appears, force it to fill the screen (belt-and-suspenders on top
# of the WM, in case the game opens small/offset). Runs in the background.
(
  for _ in $(seq 1 120); do
    WID="$(xdotool search --name 'Stardew Valley' 2>/dev/null | head -n1)"
    if [ -n "${WID}" ]; then
      wmctrl -i -r "${WID}" -b add,maximized_vert,maximized_horz 2>/dev/null || true
      xdotool windowmove "${WID}" 0 0 windowsize "${WID}" 100% 100% 2>/dev/null || true
      break
    fi
    sleep 1
  done
) &

cleanup() { kill "${XVFB_PID}" 2>/dev/null || true; }
trap cleanup EXIT

# ── 5. Optional VNC + web console (world creation / admin) ───────────────────────
# Attach a VNC server to the virtual display and serve it over the web via noVNC.
# Use this to create your co-op farm the first time (there's no save yet, so the game
# sits at the title screen — connect and click through New -> Co-op -> sleep to save).
# SECURITY: bind ports to Tailscale/localhost in docker-compose.yml. Never expose publicly.
if [ -n "${VNC_PASSWORD:-}" ]; then
  echo ">> Starting VNC (:5900) + noVNC web (:6080) ..."
  mkdir -p "${HOME}/.vnc"
  x11vnc -storepasswd "${VNC_PASSWORD}" "${HOME}/.vnc/passwd" >/dev/null 2>&1
  x11vnc -display "${DISPLAY}" -rfbauth "${HOME}/.vnc/passwd" \
         -forever -shared -noxdamage -rfbport 5900 -bg -quiet
  websockify --web=/usr/share/novnc 6080 localhost:5900 >/dev/null 2>&1 &
  echo "   Web console: http://<host>:6080/vnc.html"
else
  echo ">> VNC disabled (VNC_PASSWORD not set)."
fi

# ── 6. Auto-start the unattended server, driven by the mod's own log ─────────────
# The mod only auto-enables if the save loads already in host mode; with a headless
# autoloader it doesn't, so it stays off (and farmhand joins NPE). We watch its log for
# "Server Mode On!" and press F9 ONLY while it's still off — so we never toggle it back.
# SERVER_AUTOSTART_DELAY = grace period before the first check; set 0 to disable (use VNC).
echo ">> Launching SMAPI (Stardew Valley) ..."
cd "${GAME_DIR}"

CONSOLE_LOG=/tmp/smapi-console.log
: > "${CONSOLE_LOG}"

AUTOSTART_DELAY="${SERVER_AUTOSTART_DELAY:-60}"
if [ "${AUTOSTART_DELAY}" -gt 0 ] 2>/dev/null; then
  (
    # wait for the game window to exist, then a grace period for the save to load
    for _ in $(seq 1 180); do
      xdotool search --name 'Stardew Valley' >/dev/null 2>&1 && break
      sleep 1
    done
    sleep "${AUTOSTART_DELAY}"
    # press F9 until the mod confirms it's on (log line), then stop
    for _ in $(seq 1 20); do
      if grep -q 'Server Mode On!' "${CONSOLE_LOG}" 2>/dev/null; then
        echo ">> Unattended server is ON."
        exit 0
      fi
      WID="$(xdotool search --name 'Stardew Valley' 2>/dev/null | head -n1)"
      if [ -n "${WID}" ]; then
        xdotool windowactivate --sync "${WID}" 2>/dev/null || true
        xdotool key F9 2>/dev/null || true
        echo ">> Server mode off — pressed F9, waiting for confirmation ..."
      fi
      sleep 12   # long enough for the mod to log the state change before re-checking
    done
    echo ">> WARNING: could not confirm 'Server Mode On!' — check the VNC console."
  ) &
fi

# Tee the game's output so both `docker logs` and the watcher above can read it.
exec ./StardewModdingAPI > >(tee -a "${CONSOLE_LOG}") 2>&1

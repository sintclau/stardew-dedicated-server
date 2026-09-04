#!/usr/bin/env bash
# Extract the Linux game files from a GOG offline installer (.sh) into ./game.
#
# A GOG MojoSetup ".sh" installer is also a valid ZIP archive; the actual game lives
# under data/noarch/game/. We pull just that out — no need to run the installer, and
# it works on macOS/Linux alike (only needs `unzip`).
#
# Usage:
#   scripts/extract-game.sh /path/to/stardew_valley.sh [dest_dir]
#
# Steam users: copy your Linux "Stardew Valley" install dir into ./game instead.
set -euo pipefail

INSTALLER="${1:?Usage: extract-game.sh /path/to/stardew_valley.sh [dest_dir]}"
DEST="${2:-./game}"

if [ ! -f "${INSTALLER}" ]; then
  echo "!! Installer not found: ${INSTALLER}"; exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo ">> Extracting game files from ${INSTALLER} ..."
# Only the game payload; skip the ~hundreds of MB of soundtrack/extras.
# NOTE: a GOG MojoSetup .sh has a shell/makeself header before the zip, so unzip prints
# "extra bytes at beginning" and exits 1 (a warning, not a failure). Treat 0 and 1 as OK;
# only >=2 is a real error. (Without this, `set -e` would abort right here.)
set +e
unzip -q "${INSTALLER}" 'data/noarch/game/*' -d "${TMP}"
rc=$?
set -e
if [ "${rc}" -gt 1 ]; then
  echo "!! unzip failed (exit ${rc}) — is the installer complete / a valid GOG Linux .sh?"
  exit 1
fi

if [ ! -d "${TMP}/data/noarch/game" ]; then
  echo "!! No data/noarch/game/ inside the installer — is this the Linux GOG installer?"
  exit 1
fi

mkdir -p "${DEST}"
cp -a "${TMP}/data/noarch/game/." "${DEST}/"

# Make the launchers executable (zip loses the +x bit).
chmod +x "${DEST}/StardewValley" 2>/dev/null || true
chmod +x "${DEST}/Stardew Valley" 2>/dev/null || true

echo ">> Done. Game files in ${DEST}:"
ls "${DEST}" | head -n 20
echo ">> Sanity check:"
[ -e "${DEST}/Stardew Valley.dll" ] && echo "   OK: 'Stardew Valley.dll' present (Linux .NET build)" \
  || echo "   !! 'Stardew Valley.dll' missing — wrong build?"

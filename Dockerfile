# syntax=docker/dockerfile:1
#
# Stardew Valley 1.6 headless dedicated server — bring your own Linux game build.
#
# Base is Debian (glibc) on purpose: the Linux Stardew build ships a *self-contained*
# .NET runtime (libcoreclr.so, libhostfxr.so, ...), which is glibc-linked. Alpine (musl)
# would need gcompat shims; Debian just works.
#
# The game files are NOT baked into the image (you own the game — mount your own copy).
# SMAPI + the headless "unattended server" mod ARE baked (both freely redistributable).
FROM debian:bookworm-slim

# Check https://smapi.io for the current version compatible with your Stardew version.
ARG SMAPI_VERSION=4.5.2
# Prebuilt "unattended server" mod (theghost99) — .NET6, fixes for SV 1.6.9+ / SMAPI 4.1.7+.
ARG UNATTENDED_MOD_URL="https://raw.githubusercontent.com/theghost99/StardewUnattendedServer/main/StardewUnattendedServer%201.0.5.zip"

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:99 \
    # No GPU in the container → software OpenGL via Mesa llvmpipe.
    LIBGL_ALWAYS_SOFTWARE=1 \
    GALLIUM_DRIVER=llvmpipe \
    # Saves/config land under /data (a mounted volume) instead of a throwaway HOME.
    HOME=/data/home \
    XDG_CONFIG_HOME=/data/home/.config

RUN apt-get update && apt-get install -y --no-install-recommends \
      xvfb x11-xserver-utils xauth xdotool \
      libgl1-mesa-dri libglx-mesa0 libgl1 libegl1 \
      libopenal1 libsdl2-2.0-0 libvorbisfile3 \
      libgdiplus libicu72 libssl3 zlib1g \
      procps unzip curl ca-certificates gettext-base tini \
 && rm -rf /var/lib/apt/lists/*

# SMAPI installer — run at container start against the mounted game (see entrypoint).
RUN curl -fsSL -o /tmp/smapi.zip \
      "https://github.com/Pathoschild/SMAPI/releases/download/${SMAPI_VERSION}/SMAPI-${SMAPI_VERSION}-installer.zip" \
 && unzip -q /tmp/smapi.zip -d /opt \
 && mv /opt/SMAPI*installer /opt/smapi-installer \
 && rm /tmp/smapi.zip

# Headless "unattended server" mod (baked). Keeps the host farmer alive: auto-sleep,
# festivals, community-center, etc. Activates when a multiplayer host save is loaded.
RUN curl -fsSL -o /tmp/mod.zip "${UNATTENDED_MOD_URL}" \
 && unzip -q /tmp/mod.zip -d /opt/baked-mods \
 && rm /tmp/mod.zip

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Stardew LAN / direct-IP multiplayer port. Friends use "Join LAN Game" -> your IP.
EXPOSE 24642/udp

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]

# Generic VB6 build image.
#
# Installs Visual Studio 6 / VB6 Enterprise + Service Pack 6 into a Wine
# prefix at image-build time, so `docker run` starts in seconds. The image is
# project-agnostic: it builds whatever project you mount at /work (see
# entrypoint.sh).
#
# Build context layout:
#   media/cd/    Visual Studio 6 Enterprise CD (populated by scripts/prepare-media.sh)
#   media/sp6/   VB6 Service Pack 6 CABs      (populated by scripts/prepare-media.sh)
#   vendor/      setup response file (telyn_VB6.STF) + reference material
#   scripts/     installer + component registration helpers
#   entrypoint.sh  -> installed as /usr/local/bin/build-project.sh
#
#   docker build -t vb6-builder:sp6 .

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# WineHQ stable (Ubuntu jammy), plus the bits the VB6 installer needs.
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      wget gnupg2 software-properties-common apt-transport-https \
      ca-certificates lsb-release sudo \
 && wget -q -O /tmp/winehq.key https://dl.winehq.org/wine-builds/winehq.key \
 && apt-key add /tmp/winehq.key \
 && echo "deb https://dl.winehq.org/wine-builds/ubuntu/ jammy main" \
      > /etc/apt/sources.list.d/winehq.list \
 && apt-get update \
 && apt-get install -y --install-recommends winehq-stable xvfb cabextract winbind \
 && apt-get install -y --no-install-recommends winetricks xdotool \
 && rm -rf /var/lib/apt/lists/*

# 32-bit prefix: VB6 is a 32-bit toolchain.
ENV WINEPREFIX=/wine \
    WINEARCH=win32 \
    WINEDEBUG=-all \
    DISPLAY=:99 \
    WINEDLLOVERRIDES=mscoree,mshtml=

# Install media + tooling.
COPY media/cd/ /media/cd/
COPY media/sp6/ /media/sp6/
COPY vendor/ /vendor/
COPY scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# Install VB6 Enterprise + SP6 into the prefix.
# VBP_PRODUCT_KEY is optional: the retail CD carries its own PID, so the telyn
# response file installs without a key.
RUN VBP_PRODUCT_KEY="$(cat /run/secrets/vb6_product_key 2>/dev/null || true)" \
    VBP_STF=/vendor/telyn_VB6.STF \
    install-vb6.sh

# Register the standard SP6 redistributable controls/runtime.
RUN register-base.sh

COPY entrypoint.sh /usr/local/bin/build-project.sh
RUN chmod +x /usr/local/bin/build-project.sh

ENTRYPOINT ["/usr/local/bin/build-project.sh"]

#!/bin/bash
# Turns Raspberry Pi OS Lite (64-bit) into the Seed Drop Controller.
#
#   On a Pi:        sudo ./install.sh        then reboot
#   Image builder:  runs this inside the image with SEEDCTL_IN_CHROOT=1
#
# Safe to run again to update: settings in seedctl.conf on the SD card are kept.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
IN_CHROOT="${SEEDCTL_IN_CHROOT:-0}"
log() { echo "[seedctl] $*"; }

[ "$(id -u)" = 0 ] || { echo "Run with sudo"; exit 1; }
[ "$(dpkg --print-architecture)" = arm64 ] || { echo "This needs 64-bit Raspberry Pi OS (arm64)"; exit 1; }
BOOT=/boot/firmware; [ -d "$BOOT" ] || BOOT=/boot

# ---- packages ----
export DEBIAN_FRONTEND=noninteractive
log "Installing packages (cage, Chromium)..."
apt-get update -q
if apt-cache show chromium 2>/dev/null | grep -q '^Package: chromium$'; then CHROMIUM=chromium; else CHROMIUM=chromium-browser; fi
apt-get install -y -q --no-install-recommends cage wlr-randr "$CHROMIUM" python3 fonts-dejavu-core rfkill iw
apt-get clean

# ---- kiosk user ----
if ! id seedctl >/dev/null 2>&1; then
  log "Creating user seedctl (runs the screen, no password, no sudo)"
  useradd --create-home --shell /usr/sbin/nologin seedctl
fi
for g in video render input audio; do getent group "$g" >/dev/null && usermod -aG "$g" seedctl; done

# ---- app + scripts ----
log "Installing the controller app to /opt/seedctl"
rm -rf /opt/seedctl
mkdir -p /opt/seedctl/bin
cp -r "$SRC/app" /opt/seedctl/app
install -m 0755 "$SRC/bin/seedctl-setup" "$SRC/bin/seedctl-kiosk" "$SRC/bin/seedctl-cage" "$SRC/bin/seedctl-savelog" /opt/seedctl/bin/
# The app loads its settings from config.js; seedctl-setup writes the real file to /run at boot.
ln -sf /run/seedctl/config.js /opt/seedctl/app/config.js
[ -f "$SRC/VERSION" ] && cp "$SRC/VERSION" /opt/seedctl/VERSION

# ---- services ----
install -m 0644 "$SRC/systemd/seedctl-setup.service" "$SRC/systemd/seedctl-kiosk.service" /etc/systemd/system/
install -m 0644 "$SRC/systemd/seedctl-kiosk.pam" /etc/pam.d/seedctl-kiosk
systemctl enable seedctl-setup.service seedctl-kiosk.service
systemctl set-default graphical.target
# getty@tty1 stays installed: the kiosk replaces it while running, and it comes
# back as a login prompt if the kiosk fails or seedctl-off is on the boot partition.
systemctl enable getty@tty1.service 2>/dev/null || true

# ---- settings file on the SD card's boot partition ----
if [ -f "$BOOT/seedctl.conf" ]; then
  log "Keeping existing $BOOT/seedctl.conf"
else
  cp "$SRC/seedctl.conf" "$BOOT/seedctl.conf"
  log "Wrote $BOOT/seedctl.conf (set DRONE_SSID before flying)"
fi

# ---- quiet boot ----
CMDLINE="$BOOT/cmdline.txt"
if [ -f "$CMDLINE" ]; then
  for opt in quiet loglevel=3 logo.nologo vt.global_cursor_default=0; do
    grep -qw -- "$opt" "$CMDLINE" || sed -i "1 s/\$/ $opt/" "$CMDLINE"
  done
fi
CONFIGTXT="$BOOT/config.txt"
if [ -f "$CONFIGTXT" ] && ! grep -q '^disable_splash=1' "$CONFIGTXT"; then
  printf '\n# Seed Drop Controller\ndisable_splash=1\n' >> "$CONFIGTXT"
fi

if [ "$IN_CHROOT" != 1 ]; then
  systemctl daemon-reload
  systemctl restart seedctl-setup.service
  log "Done. Edit $BOOT/seedctl.conf (DRONE_SSID at least), then: sudo reboot"
else
  log "Done (image build)."
fi

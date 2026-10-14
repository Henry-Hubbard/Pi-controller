#!/bin/bash
# Run ON THE DRONE from this folder:  sudo ./install-drone.sh
# Installs the seed payload service into /home/dexi/seed_payload and starts it.
# Your payload.yaml is kept if one is already installed.
set -e
[ "$(id -u)" = 0 ] || { echo "Run with sudo"; exit 1; }
DEST=/home/dexi/seed_payload
SRC="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DEST"
cp "$SRC/payload_core.py" "$SRC/payload_node.py" "$DEST/"
if [ -f "$DEST/payload.yaml" ] && [ "$SRC" != "$DEST" ]; then
  echo "Keeping existing $DEST/payload.yaml (new default saved as payload.yaml.default)"
  cp "$SRC/payload.yaml" "$DEST/payload.yaml.default"
elif [ "$SRC" != "$DEST" ]; then
  cp "$SRC/payload.yaml" "$DEST/"
fi
chown -R dexi:dexi "$DEST"
cp "$SRC/seed-payload.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable seed-payload.service
systemctl restart seed-payload.service
sleep 4
if systemctl is-active --quiet seed-payload; then
  echo "seed-payload is running. Log: journalctl -u seed-payload -f"
else
  echo "seed-payload did not start:"; journalctl -u seed-payload -n 20 --no-pager; exit 1
fi

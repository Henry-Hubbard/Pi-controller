#!/bin/bash
# Run ON THE DRONE from the dexi-dash folder.
#
#   sudo ./install.sh            alternate dashboard on http://<drone>:8000
#                                (stock dashboard stays on :80, Node-RED on :1880)
#   sudo ./install.sh 8500       alternate dashboard on another port
#   sudo ./install.sh --replace  take over port 80 from the stock dashboard
#
# No internet needed: the dashboard has no dependencies, so it runs on the Node
# already inside the stock droneblocks/dexi-droneblocks image, with this folder
# mounted in. --restart unless-stopped brings it back after every reboot.
#
# Ports already taken on DEXI: 80 stock dashboard, 1880 Node-RED,
# 8088 mavlink2rest, 9090 rosbridge, 9999 code-server.
set -e
APP_DIR=/home/dexi/dexi-dash
IMAGE=droneblocks/dexi-droneblocks:latest

if [ "$(id -u)" != 0 ]; then echo "Run with sudo"; exit 1; fi
docker image inspect "$IMAGE" >/dev/null 2>&1 || { echo "Stock image $IMAGE not found"; exit 1; }

if [ "$1" = "--replace" ]; then
  PORT=80
  # Keeping the stock name means the boot script (start-dexi-containers.sh)
  # sees it running and does not start the stock dashboard on top of it.
  NAME=dexi-droneblocks
else
  PORT="${1:-8000}"
  NAME=dexi-dash
  case "$PORT" in 80|1880|8088|9090|9999) echo "Port $PORT is already used by DEXI. Pick another, e.g. 8000."; exit 1 ;; esac
fi

SRC="$(cd "$(dirname "$0")" && pwd)"
if [ "$SRC" != "$APP_DIR" ]; then
  mkdir -p "$APP_DIR"
  cp -r "$SRC/server.js" "$SRC/public" "$APP_DIR/"
  cp "$SRC/restore.sh" "$APP_DIR/" 2>/dev/null || true
  chown -R dexi:dexi "$APP_DIR"
fi

MOUNTS=""
for f in /etc/dexi-version /etc/dexi-platform; do [ -f "$f" ] && MOUNTS="$MOUNTS -v $f:$f:ro"; done

# Remove any earlier DEXI Dash install, whichever mode it used.
docker rm -f dexi-dash >/dev/null 2>&1 || true
if [ "$NAME" = dexi-droneblocks ]; then docker rm -f dexi-droneblocks >/dev/null 2>&1 || true; fi

docker run -d --restart unless-stopped \
  --pid=host --network host -e PORT="$PORT" \
  -v /proc/device-tree/model:/etc/device-model:ro \
  -v "$APP_DIR":/dash:ro $MOUNTS \
  --label dexi.dashboard=dexi-dash \
  --name "$NAME" \
  --entrypoint node "$IMAGE" /dash/server.js >/dev/null

sleep 2
IP=$(hostname -I | awk '{print $1}')
if curl -fsS "http://localhost:$PORT/api/version" >/dev/null; then
  echo "DEXI Dash:        http://$IP:$PORT/"
else
  echo "Container started but did not answer on :$PORT. Check: docker logs $NAME"; exit 1
fi
if [ "$PORT" != 80 ]; then
  docker ps --format '{{.Names}}' | grep -qx dexi-droneblocks && echo "Stock dashboard:  http://$IP/   (unchanged)"
fi
docker ps --format '{{.Names}}' | grep -qx dexi-node-red && echo "Node-RED:         http://$IP:1880/   (unchanged)"

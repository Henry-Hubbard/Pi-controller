#!/bin/bash
# Remove DEXI Dash and make sure the stock dashboard is running on port 80.
#   sudo ./restore.sh
set -e
docker rm -f dexi-dash >/dev/null 2>&1 || true
# Only remove the port-80 container if it is DEXI Dash (installed with --replace).
if [ "$(docker inspect -f '{{index .Config.Labels "dexi.dashboard"}}' dexi-droneblocks 2>/dev/null)" = "dexi-dash" ]; then
  docker rm -f dexi-droneblocks >/dev/null
fi
/usr/local/bin/start-dexi-containers.sh

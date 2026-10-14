#!/bin/bash
# Run FROM YOUR LAPTOP while joined to the drone's network:
#   ./deploy.sh                      alternate dashboard at http://192.168.4.1:8000
#   ./deploy.sh 10.0.0.42            drone on your Wi-Fi
#   ./deploy.sh 192.168.4.1 8500     another port
#   ./deploy.sh 192.168.4.1 --replace   take over port 80 from the stock dashboard
# Copies this folder to the drone and runs install.sh there. Password: dexi
set -e
DRONE="${1:-192.168.4.1}"
MODE="${2:-}"
cd "$(dirname "$0")"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"   # all DEXI boards share a host key
tar czf - server.js public install.sh restore.sh | ssh $SSH_OPTS dexi@"$DRONE" \
  'mkdir -p ~/dexi-dash && tar xzf - -C ~/dexi-dash && chmod +x ~/dexi-dash/*.sh'
# Second connection gets a terminal, so sudo can ask for the password (dexi).
ssh -t $SSH_OPTS dexi@"$DRONE" "cd ~/dexi-dash && sudo ./install.sh $MODE"

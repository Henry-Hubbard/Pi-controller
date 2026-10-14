#!/bin/bash
# Build the image inside Docker:  ./build/docker-build.sh [raspios-lite.img.xz]
# On an Apple Silicon Mac this runs natively. On an Intel/AMD machine, first run:
#   docker run --privileged --rm tonistiigi/binfmt --install arm64
set -euo pipefail
cd "$(dirname "$0")/.."
docker build --platform linux/arm64 -t seedctl-builder build
docker run --rm --privileged --platform linux/arm64 -v /dev:/dev -v "$PWD":/work \
  -e ADMIN_USER -e ADMIN_PASSWORD seedctl-builder "$@"

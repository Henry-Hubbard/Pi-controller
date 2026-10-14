# Build environment for build-image.sh, for Macs and Windows (or any Docker host).
FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      xz-utils parted e2fsprogs util-linux mount curl ca-certificates openssl qemu-user-static \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /work
ENTRYPOINT ["/bin/bash", "/work/build/build-image.sh"]

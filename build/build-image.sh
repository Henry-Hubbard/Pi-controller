#!/bin/bash
# Builds a flashable Seed Drop Controller image from Raspberry Pi OS Lite (64-bit).
#
#   sudo ./build/build-image.sh                     download the latest Pi OS Lite
#   sudo ./build/build-image.sh raspios-lite.img.xz use a file you already have
#
# Needs a Linux machine (or ./build/docker-build.sh on a Mac or Windows),
# root, and about 8 GB free. On a non-ARM Linux host, arm64 emulation must be
# registered first:  docker run --privileged --rm tonistiigi/binfmt --install arm64
#
# Output: out/seedctl-os.img  (flash it with Raspberry Pi Imager, "Use custom")
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${1:-https://downloads.raspberrypi.com/raspios_lite_arm64_latest}"
OUT_DIR="$ROOT/out"
IMG="$OUT_DIR/seedctl-os.img"
CACHE="$ROOT/build/cache"
GROW_MB="${GROW_MB:-1536}"                # room for Chromium
ADMIN_USER="${ADMIN_USER:-seedadmin}"     # for SSH / maintenance; the screen runs as 'seedctl'
ADMIN_PASSWORD="${ADMIN_PASSWORD:-seedctl}"
MNT=""; LOOP_ROOT=""; LOOP_BOOT=""

log() { echo "[build] $*"; }
die() { echo "[build] ERROR: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run as root (sudo)"
for t in xz parted losetup e2fsck resize2fs chroot openssl curl; do
  command -v "$t" >/dev/null || die "missing tool: $t"
done

cleanup() {
  set +e
  if [ -n "$MNT" ]; then
    for m in dev/pts dev proc sys boot/firmware boot; do mountpoint -q "$MNT/$m" && umount -l "$MNT/$m"; done
    mountpoint -q "$MNT" && umount -l "$MNT"
    rmdir "$MNT" 2>/dev/null
  fi
  [ -n "$LOOP_BOOT" ] && losetup -d "$LOOP_BOOT" 2>/dev/null
  [ -n "$LOOP_ROOT" ] && losetup -d "$LOOP_ROOT" 2>/dev/null
}
trap cleanup EXIT

# ---- base image ----
mkdir -p "$OUT_DIR" "$CACHE"
if [ -f "$BASE" ]; then
  SRC_XZ="$BASE"
else
  SRC_XZ="$CACHE/raspios-lite-arm64.img.xz"
  if [ ! -f "$SRC_XZ" ]; then
    log "Downloading Raspberry Pi OS Lite (64-bit)..."
    curl -fL --retry 3 -o "$SRC_XZ.part" "$BASE"
    mv "$SRC_XZ.part" "$SRC_XZ"
  else
    log "Using cached $SRC_XZ (delete it to download a newer one)"
  fi
fi
log "Unpacking..."
case "$SRC_XZ" in
  *.xz) xz -dc "$SRC_XZ" > "$IMG" ;;
  *.img) cp "$SRC_XZ" "$IMG" ;;
  *) die "base image must be .img or .img.xz" ;;
esac

# ---- make room ----
log "Growing the root partition by ${GROW_MB} MB"
truncate -s "+${GROW_MB}M" "$IMG"
parted -s "$IMG" resizepart 2 100%

# Partition offsets straight from the table (no udev needed, works in Docker).
part() { parted -sm "$IMG" unit B print | awk -F: -v n="$1" '$1==n {gsub("B","",$2); gsub("B","",$4); print $2, $4}'; }
read -r BOOT_OFF BOOT_SIZE < <(part 1)
read -r ROOT_OFF ROOT_SIZE < <(part 2)
[ -n "$ROOT_OFF" ] || die "could not read the partition table"
LOOP_BOOT=$(losetup -f --show --offset "$BOOT_OFF" --sizelimit "$BOOT_SIZE" "$IMG")
LOOP_ROOT=$(losetup -f --show --offset "$ROOT_OFF" --sizelimit "$ROOT_SIZE" "$IMG")
e2fsck -pf "$LOOP_ROOT" || true
resize2fs "$LOOP_ROOT"

# ---- mount ----
MNT=$(mktemp -d)
mount "$LOOP_ROOT" "$MNT"
if [ -d "$MNT/boot/firmware" ]; then BOOTDIR="$MNT/boot/firmware"; else BOOTDIR="$MNT/boot"; fi
mount "$LOOP_BOOT" "$BOOTDIR"
mount --bind /dev "$MNT/dev"; mount --bind /dev/pts "$MNT/dev/pts"
mount -t proc proc "$MNT/proc"; mount -t sysfs sys "$MNT/sys"

if [ "$(uname -m)" != aarch64 ]; then
  QEMU=$(command -v qemu-aarch64-static || true)
  [ -n "$QEMU" ] && cp "$QEMU" "$MNT/usr/bin/"
fi
cp --remove-destination /etc/resolv.conf "$MNT/etc/resolv.conf"
PRELOAD="$MNT/etc/ld.so.preload"; [ -f "$PRELOAD" ] && mv "$PRELOAD" "$PRELOAD.seedctl"

# ---- install ----
log "Installing the controller (this is the slow part under emulation)..."
rm -rf "$MNT/tmp/seedctl"
cp -r "$ROOT/controller" "$MNT/tmp/seedctl"
[ -f "$ROOT/VERSION" ] && cp "$ROOT/VERSION" "$MNT/tmp/seedctl/VERSION"
chroot "$MNT" /usr/bin/env SEEDCTL_IN_CHROOT=1 /bin/bash /tmp/seedctl/install.sh
rm -rf "$MNT/tmp/seedctl"

# ---- first-boot admin account + SSH ----
HASH=$(openssl passwd -6 "$ADMIN_PASSWORD")
echo "$ADMIN_USER:$HASH" > "$BOOTDIR/userconf.txt"
touch "$BOOTDIR/ssh"
if [ -d "$MNT/etc/cloud" ]; then
  log "NOTE: this base image uses cloud-init. If the admin login does not work, set the user"
  log "      with Raspberry Pi Imager's customisation when flashing instead."
fi

# ---- tidy ----
[ -f "$PRELOAD.seedctl" ] && mv "$PRELOAD.seedctl" "$PRELOAD"
rm -f "$MNT/usr/bin/qemu-aarch64-static"
sync
log "Built $IMG"
log "Admin login (SSH or keyboard): $ADMIN_USER / $ADMIN_PASSWORD  (change it: passwd)"
log "Before first boot, set DRONE_SSID in seedctl.conf on the card's boot partition."

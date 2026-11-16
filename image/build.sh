#!/bin/bash
# Bouwt het EventVOX-Pi-image: het officiële Raspberry Pi OS Lite (64-bit) met EventVOX-Pi, Chromium en Raspberry Pi
# Connect erop, en een eerste-start-dienst die de kiosk inricht voor de gebruiker uit Raspberry Pi Imager.
# Draait als root op een arm64-Linux (GitHub Actions: ubuntu-24.04-arm); zie .github/workflows/release.yml.
#
#   sudo image/build.sh <basis-image.img.xz-URL> <versie> <uitvoermap>
#
# Het basis-image komt uit de officiële lijst van Raspberry Pi Imager (de workflow zoekt hem op), zodat Imager de
# instellingen (gebruiker, wifi, SSH, Connect) op dezelfde manier toepast als op Raspberry Pi OS zelf.
set -euo pipefail
BASE_URL="$1"
VERSION="$2"
OUT="$3"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
MNT="$WORK/root"
LOOP=""
PACKAGES="labwc seatd swayidle wlrctl fonts-liberation python3 iw curl unattended-upgrades chromium rpi-connect pcscd python3-pyscard"

cleanup() {
  set +e
  for m in dev/pts dev proc sys boot/firmware ""; do mountpoint -q "$MNT/$m" && umount -l "$MNT/$m"; done
  [ -n "$LOOP" ] && losetup -d "$LOOP"
  rm -rf "$WORK/base.img"
}
trap cleanup EXIT

echo "==> Basis-image downloaden: $BASE_URL"
curl -fL --retry 3 -o "$WORK/base.img.xz" "$BASE_URL"
xz -d "$WORK/base.img.xz"
IMG="$WORK/base.img"

echo "==> Ruimte maken voor Chromium (1,5 GB erbij)"
truncate -s +1536M "$IMG"
parted -s "$IMG" resizepart 2 100%
LOOP="$(losetup -Pf --show "$IMG")"
e2fsck -fy "${LOOP}p2" || true
resize2fs "${LOOP}p2"

echo "==> Koppelen"
mkdir -p "$MNT"
mount "${LOOP}p2" "$MNT"
mount "${LOOP}p1" "$MNT/boot/firmware"
mount --bind /dev "$MNT/dev"
mount --bind /dev/pts "$MNT/dev/pts"
mount -t proc proc "$MNT/proc"
mount -t sysfs sys "$MNT/sys"
cp "$MNT/etc/resolv.conf" "$WORK/resolv.conf.orig" 2>/dev/null || true
rm -f "$MNT/etc/resolv.conf"
cp /etc/resolv.conf "$MNT/etc/resolv.conf"
# Geen diensten starten in de chroot
printf '#!/bin/sh\nexit 101\n' > "$MNT/usr/sbin/policy-rc.d"
chmod 755 "$MNT/usr/sbin/policy-rc.d"

echo "==> Pakketten installeren: $PACKAGES"
chroot "$MNT" apt-get update -q
chroot "$MNT" env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends $PACKAGES
echo "==> Opstartscherm met het EventVOX-logo"
chroot "$MNT" env DEBIAN_FRONTEND=noninteractive apt-get install -y -q rpi-splash-screen-support initramfs-tools
cp "$ROOT_DIR/pi/splash.tga" "$MNT/tmp/eventvox-splash.tga"
chroot "$MNT" configure-splash /tmp/eventvox-splash.tga || echo "::warning::opstartscherm instellen mislukt"
rm -f "$MNT/tmp/eventvox-splash.tga"
chroot "$MNT" apt-get clean
rm -rf "$MNT/var/lib/apt/lists/"*

echo "==> EventVOX-Pi $VERSION en de eerste-start-dienst"
mkdir -p "$MNT/opt/eventvox-pi-kit"
cp -r "$ROOT_DIR/install.sh" "$ROOT_DIR/pi" "$MNT/opt/eventvox-pi-kit/"
rm -rf "$MNT/opt/eventvox-pi-kit/pi/__pycache__"
install -m 0755 "$ROOT_DIR/image/firstboot.sh" "$MNT/usr/local/sbin/eventvox-pi-firstboot"
install -m 0644 "$ROOT_DIR/image/eventvox-pi-firstboot.service" "$MNT/etc/systemd/system/eventvox-pi-firstboot.service"
ln -sf /etc/systemd/system/eventvox-pi-firstboot.service "$MNT/etc/systemd/system/multi-user.target.wants/eventvox-pi-firstboot.service"
echo "$VERSION" > "$MNT/etc/eventvox-pi-image"

echo "==> Opruimen"
rm -f "$MNT/usr/sbin/policy-rc.d" "$MNT/etc/resolv.conf"
[ -e "$WORK/resolv.conf.orig" ] && cp -P "$WORK/resolv.conf.orig" "$MNT/etc/resolv.conf"
cleanup_mounts() { for m in dev/pts dev proc sys boot/firmware ""; do mountpoint -q "$MNT/$m" && umount "$MNT/$m"; done; }
cleanup_mounts
# Vrije ruimte op nul: comprimeert veel beter
command -v zerofree >/dev/null && zerofree "${LOOP}p2"
losetup -d "$LOOP"
LOOP=""

echo "==> Comprimeren"
mkdir -p "$OUT"
NAME="eventvox-pi-$VERSION.img"
mv "$IMG" "$OUT/$NAME"
EXTRACT_SIZE="$(stat -c %s "$OUT/$NAME")"
EXTRACT_SHA="$(sha256sum "$OUT/$NAME" | cut -d' ' -f1)"
xz -T0 -6 "$OUT/$NAME"
echo "$EXTRACT_SIZE $EXTRACT_SHA" > "$OUT/$NAME.extract"
ls -lh "$OUT"

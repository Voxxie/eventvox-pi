#!/bin/bash
# Opstarttest van het SD-kaart-image in een nagebootste Raspberry Pi 3B (QEMU), zonder echte Pi. Vangt een image dat niet
# opstart (zoals 0.0.6 tot 0.0.9) of een eerste inrichting die vastloopt (zoals 0.0.10 bij Raspberry Pi Connect).
#   image/qemu-test.sh <image.img of .img.xz> [werkmap]
# 1. Een gebruiker zoals Raspberry Pi Imager die maakt (cloud-init user-data op de bootpartitie).
# 2. Starten tot de eerste inrichting klaar is: Linux start, de kaart wordt vergroot (en herstart), de eerste inrichting
#    draait en herstart (QEMU stopt bij elke herstart; hoogstens 5 starts).
# 3. Controle op de kaart (debugfs, geen root nodig): het logboek van de eerste start eindigt met "klaar", de dienst
#    staat uit, EventVOX-Pi staat in /opt/eventvox-pi.
# 4. Nog een start: Linux komt tot het inlogscherm op de seriële console.
# Wat QEMU niet kan nabootsen (scherm, wifi, HDMI, Chromium op het scherm) test dit niet.
# Nodig: qemu-system-aarch64 (raspi3b), mtools, e2fsprogs (debugfs), openssl, python3.
set -uo pipefail
IMG_IN="${1:?Gebruik: image/qemu-test.sh <image.img of .img.xz> [werkmap]}"
WORK="${2:-$(mktemp -d)}"
FIRST_S="${QEMU_FIRST_TIMEOUT:-2400}"
SECOND_S="${QEMU_SECOND_TIMEOUT:-900}"
mkdir -p "$WORK"
fail() { echo "FOUT: $*" >&2; [ -f "$WORK/boot1.log" ] && { echo "--- laatste regels eerste start:"; tail -n 40 "$WORK/boot1.log"; } >&2; exit 1; }

echo "==> Image uitpakken naar $WORK/sd.img (8 GB: QEMU wil een macht van twee)"
case "$IMG_IN" in
  *.xz) xz -dc "$IMG_IN" > "$WORK/sd.img" || fail "uitpakken" ;;
  *) cp "$IMG_IN" "$WORK/sd.img" ;;
esac
truncate -s 8G "$WORK/sd.img"

part() {  # nummer -> "begin aantal" in sectoren, uit de MBR
  python3 - "$WORK/sd.img" "$1" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read(512)
e = d[446 + 16 * (int(sys.argv[2]) - 1):462 + 16 * (int(sys.argv[2]) - 1)]
print(*struct.unpack('<II', e[8:16]))
PY
}
read -r BOOT_START _ < <(part 1)
BOOT="$WORK/sd.img@@$((BOOT_START * 512))"
for f in kernel8.img bcm2710-rpi-3-b.dtb initramfs8; do mcopy -o -i "$BOOT" "::/$f" "$WORK/$f" || fail "$f niet op de bootpartitie"; done

echo "==> Gebruiker zoals Raspberry Pi Imager (cloud-init)"
HASH="$(openssl passwd -6 eventvox-test)"
cat > "$WORK/user-data" <<UD
#cloud-config
hostname: qemu-test
manage_etc_hosts: true
users:
- name: kiosk
  groups: users,adm,dialout,audio,netdev,video,plugdev,input,render,sudo
  shell: /bin/bash
  lock_passwd: false
  passwd: $HASH
  sudo: ALL=(ALL) NOPASSWD:ALL
UD
mcopy -o -i "$BOOT" "$WORK/user-data" ::/user-data || fail "user-data schrijven"

# Bij de eerste start geeft Raspberry Pi OS de kaart een nieuwe schijf-ID (cmdline.txt en fstab); in QEMU komt die niet
# altijd in de nagebootste kaart terecht (op een echte Pi wel). Daarom vóór elke start de schijf-ID op de kaart gelijk
# zetten aan root=PARTUUID in cmdline.txt, zoals op een echte kaart.
sync_disk_id() {
  python3 - "$WORK/sd.img" "$1" <<'PY'
import re, struct, sys
m = re.search(r'root=PARTUUID=([0-9a-f]{8})-02', sys.argv[2])
if m:
    with open(sys.argv[1], 'r+b') as f:
        f.seek(440)
        if f.read(4) != struct.pack('<I', int(m.group(1), 16)):
            f.seek(440)
            f.write(struct.pack('<I', int(m.group(1), 16)))
            print('    schijf-ID gelijkgezet aan cmdline.txt:', m.group(1))
PY
}

boot() {  # logbestand, seconden; de cmdline zoals de firmware hem leest, met de console op de seriële poort van QEMU
  local cmd
  cmd="$(mtype -i "$BOOT" ::/cmdline.txt | tr -d '\r\n' | sed 's/console=serial0,115200/console=ttyAMA1,115200/; s/console=tty1//')"
  sync_disk_id "$cmd"
  echo "    cmdline: $cmd"
  timeout "$2" qemu-system-aarch64 -M raspi3b -m 1G -smp 4 -kernel "$WORK/kernel8.img" -dtb "$WORK/bcm2710-rpi-3-b.dtb" \
    -initrd "$WORK/initramfs8" -no-reboot -drive "file=$WORK/sd.img,format=raw,if=sd" \
    -append "$cmd watchdog_disarm=0 dwc_otg.fiq_fsm_enable=0" -display none -serial "file:$1" -serial null \
    -usb -device usb-net,netdev=n0 -netdev user,id=n0 >/dev/null 2>&1
}

# Raspberry Pi OS herstart zelf na het vergroten van de kaart, en de eerste inrichting herstart als hij klaar is: QEMU
# stopt bij elke herstart (-no-reboot). Opnieuw starten tot de inrichting klaar is (hoogstens 5 keer, samen FIRST_S).
# De rootpartitie rechtstreeks in het image lezen (debugfs met offset): niets kopiëren
ROOTFS=""
fsfile() { debugfs -R "cat $1" "$ROOTFS" 2>/dev/null; }
deadline=$(( $(date +%s) + FIRST_S ))
done_ok=0
for n in 1 2 3 4 5; do
  left=$(( deadline - $(date +%s) ))
  [ "$left" -gt 30 ] || break
  echo "==> Start $n (hoogstens $left s)"
  start=$(date +%s)
  boot "$WORK/boot$n.log" "$left"
  code=$?
  echo "    na $(( $(date +%s) - start )) s gestopt (code $code)"
  cp "$WORK/boot$n.log" "$WORK/boot1.log" 2>/dev/null || true  # de laatste, voor fail()
  [ "$code" = 124 ] && fail "start $n liep niet af binnen de tijd (vastgelopen?)"
  grep -aq "Run /init" "$WORK/boot$n.log" || fail "Linux startte niet (geen /init) bij start $n"
  read -r ROOT_START _ < <(part 2)
  ROOTFS="$WORK/sd.img?offset=$((ROOT_START * 512))"
  fsfile /var/log/eventvox-pi-firstboot.log > "$WORK/firstboot.log"
  if grep -q "== klaar" "$WORK/firstboot.log"; then done_ok=1; break; fi
done

echo "==> Controle op de kaart"
tail -n 20 "$WORK/firstboot.log"
[ "$done_ok" = 1 ] || fail "de eerste inrichting werd niet afgerond (zie het logboek hierboven)"
debugfs -R "stat /etc/systemd/system/multi-user.target.wants/eventvox-pi-firstboot.service" "$ROOTFS" 2>&1 | grep -q "not found\|File not found" \
  || fail "de eerste start staat nog aan"
[ -n "$(fsfile /opt/eventvox-pi/VERSION)" ] || fail "geen /opt/eventvox-pi/VERSION"
echo "ok   eerste inrichting klaar na $n starts: EventVOX-Pi $(fsfile /opt/eventvox-pi/VERSION)"

echo "==> Start na de inrichting (hoogstens $SECOND_S s): tot het inlogscherm"
( boot "$WORK/after.log" "$SECOND_S" ) &
QPID=$!
end=$(( $(date +%s) + SECOND_S ))
while [ "$(date +%s)" -lt "$end" ] && kill -0 "$QPID" 2>/dev/null; do
  grep -aq "login:" "$WORK/after.log" 2>/dev/null && break
  sleep 5
done
pkill -f "file:$WORK/after.log" 2>/dev/null; wait "$QPID" 2>/dev/null
grep -aq "login:" "$WORK/after.log" || { tail -n 40 "$WORK/after.log"; fail "de start na de inrichting kwam niet tot het inlogscherm"; }
echo "ok   start na de inrichting: Linux tot het inlogscherm"
echo "Opstarttest geslaagd"

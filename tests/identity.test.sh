#!/usr/bin/env bash
# Eigen naam en serienummer per toestel (pi/identity.sh), op een nagebootst systeem (EVX_PI_ROOT): een Raspberry Pi, een pc
# met een serienummer in het BIOS, een pc met een standaardtekst ("To Be Filled By O.E.M."), en een gekloonde schijf.
# hostname, hostnamectl en ssh-keygen zijn nagebootst; raspi-config ook (alleen in de Pi-ronde).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail() { echo "FOUT: $*"; exit 1; }

setup() {
  rm -rf "$T/r" "$T/bin" && mkdir -p "$T/r/proc/device-tree" "$T/r/sys/class/dmi/id" "$T/r/etc/ssh" "$T/bin"
  printf '127.0.0.1\tlocalhost\n127.0.1.1\t%s\n' "$1" > "$T/r/etc/hosts"
  echo "$1" > "$T/hostname"
  touch "$T/r/etc/ssh/ssh_host_ed25519_key"; : > "$T/calls"
  printf '#!/bin/bash\ncat "%s/hostname"\n' "$T" > "$T/bin/hostname"
  printf '#!/bin/bash\necho "hostnamectl $*" >> "%s/calls"; echo "$2" > "%s/hostname"\n' "$T" "$T" > "$T/bin/hostnamectl"
  printf '#!/bin/bash\necho "ssh-keygen $*" >> "%s/calls"\n' "$T" > "$T/bin/ssh-keygen"
  chmod +x "$T/bin/"*
}
run() { PATH="$T/bin:$PATH" EVX_PI_ROOT="$T/r" bash "$ROOT/pi/identity.sh"; }

# --- Raspberry Pi: serienummer uit /proc/cpuinfo, raspi-config zet de naam (zoals altijd) ---
setup raspberrypi
printf 'Raspberry Pi 4 Model B Rev 1.4\0' > "$T/r/proc/device-tree/model"
printf 'Hardware\t: BCM2835\nSerial\t\t: 10000000abcdef12\n' > "$T/r/proc/cpuinfo"
printf '#!/bin/bash\necho "raspi-config $*" >> "%s/calls"\n' "$T" > "$T/bin/raspi-config"; chmod +x "$T/bin/raspi-config"
run
grep -q "raspi-config nonint do_hostname eventvox-abcdef12" "$T/calls" || fail "Pi: naam niet via raspi-config: $(cat "$T/calls")"
[ "$(cat "$T/r/var/lib/eventvox-pi/identity")" = abcdef12 ] || fail "Pi: identity niet bewaard"
[ -e "$T/r/var/lib/eventvox-pi/serial" ] && fail "Pi: serial-bestand gezet (de Pi leest /proc/cpuinfo)"
echo "ok   Raspberry Pi: eventvox-abcdef12 via raspi-config, geen serial-bestand"

# --- pc met een serienummer in het BIOS (debian = de standaardnaam van de installatie) ---
setup debian
echo "Dell Inc." > "$T/r/sys/class/dmi/id/sys_vendor"
echo "OptiPlex 3060" > "$T/r/sys/class/dmi/id/product_name"
echo "5CG9ABC1X7" > "$T/r/sys/class/dmi/id/product_serial"
echo "0123abcd0123abcd0123abcd0123abcd" > "$T/r/etc/machine-id"
run
[ "$(cat "$T/r/var/lib/eventvox-pi/serial")" = 5CG9ABC1X7 ] || fail "pc: serienummer uit het BIOS niet bewaard: $(cat "$T/r/var/lib/eventvox-pi/serial")"
grep -q "hostnamectl set-hostname eventvox-g9abc1x7" "$T/calls" || fail "pc: naam niet gezet: $(cat "$T/calls")"
grep -q "^127.0.1.1	eventvox-g9abc1x7$" "$T/r/etc/hosts" || fail "pc: /etc/hosts niet bijgewerkt: $(cat "$T/r/etc/hosts")"
grep -q ssh-keygen "$T/calls" && fail "pc: nieuwe SSH-sleutels bij de eerste keer"
echo "ok   pc: serienummer uit het BIOS, naam eventvox-g9abc1x7, /etc/hosts bijgewerkt"

# Een volgende start: niets verandert
: > "$T/calls"; run
[ -s "$T/calls" ] && fail "pc: bij een gewone herstart toch iets gedaan: $(cat "$T/calls")"
echo "ok   pc: gewone herstart verandert niets"

# Een gekloonde schijf in een andere pc: eigen naam en nieuwe SSH-sleutels, ook met een eigen naam
echo "eigen-naam" > "$T/hostname"
echo "7XK2LM9" > "$T/r/sys/class/dmi/id/product_serial"
run
[ "$(cat "$T/r/var/lib/eventvox-pi/serial")" = 7XK2LM9 ] || fail "kloon: serienummer niet bijgewerkt"
grep -q "hostnamectl set-hostname eventvox-7xk2lm9" "$T/calls" || fail "kloon: geen eigen naam: $(cat "$T/calls")"
grep -q "ssh-keygen -A" "$T/calls" || fail "kloon: geen nieuwe SSH-sleutels"
[ -e "$T/r/etc/ssh/ssh_host_ed25519_key" ] && fail "kloon: oude SSH-sleutel niet weg"
echo "ok   gekloonde schijf: eigen naam en nieuwe SSH-sleutels"

# --- pc met een standaardtekst in het BIOS: afgeleid van de product-UUID; een eigen naam blijft ---
setup kassa-1
echo "To Be Filled By O.E.M." > "$T/r/sys/class/dmi/id/product_serial"
echo "4C4C4544-0042-3510-8051-B4C04F4A3732" > "$T/r/sys/class/dmi/id/product_uuid"
run
S="$(cat "$T/r/var/lib/eventvox-pi/serial")"
[[ "$S" =~ ^[0-9a-f]{16}$ ]] || fail "standaardtekst: geen afgeleid serienummer: $S"
[ "$S" = "$(printf '%s' 4c4c4544-0042-3510-8051-b4c04f4a3732 | sha256sum | cut -c1-16)" ] || fail "standaardtekst: niet van de UUID"
grep -q hostnamectl "$T/calls" && fail "een eigen naam bij de eerste keer veranderd"
echo "ok   standaardtekst in het BIOS: van de product-UUID ($S), eigen naam blijft"

# --- ook de UUID is een standaardwaarde: van /etc/machine-id ---
setup debian
echo "Default string" > "$T/r/sys/class/dmi/id/product_serial"
echo "03000200-0400-0500-0006-000700080009" > "$T/r/sys/class/dmi/id/product_uuid"
echo "0123abcd0123abcd0123abcd0123abcd" > "$T/r/etc/machine-id"
run
[ "$(cat "$T/r/var/lib/eventvox-pi/serial")" = "$(printf '%s' 0123abcd0123abcd0123abcd0123abcd | sha256sum | cut -c1-16)" ] || fail "geen machine-id gebruikt"
echo "ok   ook de UUID een standaardwaarde: van /etc/machine-id"

# --- het model in de agent (pi_health en getDeviceInfo) ---
mkdir -p "$T/sys/class/dmi/id"
model() { EVX_PI_SYSFS="$T/sys" EVX_PI_DT_MODEL="$T/dt-model" python3 -c "import sys; sys.path.insert(0, '$ROOT/pi'); import agent; print(agent.model())"; }
printf 'Raspberry Pi 4 Model B Rev 1.4\0' > "$T/dt-model"
[ "$(model)" = "Raspberry Pi 4 Model B Rev 1.4" ] || fail "model Pi: $(model)"
rm "$T/dt-model"
echo "Dell Inc." > "$T/sys/class/dmi/id/sys_vendor"; echo "OptiPlex 3060" > "$T/sys/class/dmi/id/product_name"
[ "$(model)" = "Dell Inc. OptiPlex 3060" ] || fail "model Dell: $(model)"
echo "HP" > "$T/sys/class/dmi/id/sys_vendor"; echo "HP ProDesk 600 G4 DM" > "$T/sys/class/dmi/id/product_name"
[ "$(model)" = "HP ProDesk 600 G4 DM" ] || fail "model HP: $(model)"
echo "LENOVO" > "$T/sys/class/dmi/id/sys_vendor"; echo "10T7S0AL00" > "$T/sys/class/dmi/id/product_name"
echo "ThinkCentre M720q" > "$T/sys/class/dmi/id/product_version"
[ "$(model)" = "LENOVO ThinkCentre M720q" ] || fail "model Lenovo: $(model)"
echo "To Be Filled By O.E.M." > "$T/sys/class/dmi/id/sys_vendor"; echo "System Product Name" > "$T/sys/class/dmi/id/product_name"
rm "$T/sys/class/dmi/id/product_version"
[ "$(model)" = "None" ] || fail "model standaardtekst: $(model)"
echo "ok   model: Raspberry Pi, Dell, HP, Lenovo (product_version), standaardtekst = geen model"

# --- de wifi-interface (agent en wifi.py): wlan0 op een Pi, de eerste draadloze op een pc ---
wlan() { EVX_PI_SYSFS="$T/sys" python3 -c "import sys; sys.path.insert(0, '$ROOT/pi'); import $1; print($1.wlan())"; }
mkdir -p "$T/sys/class/net/enp1s0" "$T/sys/class/net/wlp2s0/wireless"
[ "$(wlan agent)" = wlp2s0 ] || fail "agent: wifi-interface pc: $(wlan agent)"
[ "$(wlan wifi)" = wlp2s0 ] || fail "wifi.py: wifi-interface pc: $(wlan wifi)"
mkdir -p "$T/sys/class/net/wlan0/wireless"
[ "$(wlan agent)" = wlan0 ] && [ "$(wlan wifi)" = wlan0 ] || fail "wifi-interface Pi niet wlan0"
rm -rf "$T/sys/class/net/wlan0" "$T/sys/class/net/wlp2s0"
[ "$(wlan agent)" = None ] || fail "agent: zonder wifi toch een interface: $(wlan agent)"
echo "ok   wifi-interface: wlan0 op een Pi, wlp2s0 op een pc, geen zonder wifi"

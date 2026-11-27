#!/bin/bash
# Eigen naam, serienummer en SSH-sleutels per toestel (als root, bij elke start: eventvox-pi-identity.service).
#
# Raspberry Pi: het serienummer staat in /proc/cpuinfo (de agent en kiosk.sh lezen het daar zelf).
# Pc: het serienummer uit het BIOS (DMI; alleen root mag dat lezen), anders een vaste afleiding van de product-UUID of
# /etc/machine-id. Het komt in /var/lib/eventvox-pi/serial, waar de agent en kiosk.sh het lezen.
#
# Bij de eerste keer blijft een eigen naam (uit Raspberry Pi Imager of de Debian-installatie); alleen een standaardnaam
# (raspberrypi, debian, localhost) wordt eventvox-<serienummer>. Op een gekloonde SD-kaart of schijf (ander serienummer
# dan de vorige keer): een eigen naam en nieuwe SSH-sleutels, zodat niet alle toestellen hetzelfde op het netwerk staan.
#
# Tests: EVX_PI_ROOT = een map die als / geldt (proc, sys, etc, var).
R="${EVX_PI_ROOT:-}"
STATE="$R/var/lib/eventvox-pi"

# Een serienummer of UUID dat geen echt nummer is (standaardtekst van de fabrikant, alleen nullen, ...)
junk() {
  local v
  v="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
  [ "${#v}" -lt 4 ] && return 0
  [ -z "$(printf '%s' "$v" | tr -d "${v:0:1}")" ] && return 0   # één teken herhaald (00000000, ffffffff)
  case "$v" in
    *oem*|*default*|*filled*|*serial*|*none*|*notspecified*|*notapplicable*|*0123456789*|*123456789*|systemproductname) return 0 ;;
    # Een bekende UUID die veel borden delen
    03000200040005000006000700080009) return 0 ;;
  esac
  return 1
}

pc_serial() {
  local dmi="$R/sys/class/dmi/id" s
  s="$(tr -d '[:space:]' < "$dmi/product_serial" 2>/dev/null)"
  if [ -n "$s" ] && ! junk "$s"; then
    printf '%s' "$s" | tr -cd 'A-Za-z0-9-' | cut -c1-32
    return
  fi
  s="$(tr -d '[:space:]' < "$dmi/product_uuid" 2>/dev/null)"
  junk "$s" && s="$(tr -d '[:space:]' < "$R/etc/machine-id" 2>/dev/null)"
  [ -z "$s" ] && return 1
  printf '%s' "$s" | tr '[:upper:]' '[:lower:]' | sha256sum | cut -c1-16
}

set_hostname() {
  if command -v raspi-config >/dev/null 2>&1; then
    raspi-config nonint do_hostname "$1" < /dev/null
    return
  fi
  local old
  old="$(hostname)"
  hostnamectl set-hostname "$1" 2>/dev/null || echo "$1" > "$R/etc/hostname"
  # Zoals de Debian-installatie: de eigen naam op 127.0.1.1 (anders klaagt sudo over een onbekende host)
  if grep -q '^127\.0\.1\.1' "$R/etc/hosts" 2>/dev/null; then
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$1/" "$R/etc/hosts"
  else
    printf '127.0.1.1\t%s\n' "$1" >> "$R/etc/hosts"
  fi
  [ -n "$old" ] && [ "$old" != "$1" ] && echo "Naam: $old -> $1"
}

if grep -q '^Serial' "$R/proc/cpuinfo" 2>/dev/null && grep -qa 'Raspberry Pi' "$R/proc/device-tree/model" 2>/dev/null; then
  # Raspberry Pi: de laatste 8 tekens van het serienummer, zoals altijd
  SERIAL="$(grep -m1 '^Serial' "$R/proc/cpuinfo" | awk '{print $3}' | tail -c 9)"
  SHORT="$SERIAL"
  DEFAULT_NAMES="raspberrypi"
else
  SERIAL="$(pc_serial)" || exit 0
  mkdir -p "$STATE"
  # Altijd bijwerken (ook als het al klopt): de agent en kiosk.sh lezen het hier
  if [ "$(cat "$STATE/serial" 2>/dev/null)" != "$SERIAL" ]; then
    printf '%s\n' "$SERIAL" > "$STATE/serial"
    chmod 0644 "$STATE/serial"
  fi
  SHORT="$(printf '%s' "$SERIAL" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | tail -c 8)"
  DEFAULT_NAMES="raspberrypi debian localhost"
fi

PREVIOUS="$(cat "$STATE/identity" 2>/dev/null)"
[ "$PREVIOUS" = "$SERIAL" ] && exit 0
if [ -n "$PREVIOUS" ]; then
  set_hostname "eventvox-$SHORT"
  rm -f "$R"/etc/ssh/ssh_host_*
  ssh-keygen -A
else
  for n in $DEFAULT_NAMES; do
    [ "$(hostname)" = "$n" ] && set_hostname "eventvox-$SHORT" && break
  done
fi
mkdir -p "$STATE"
echo "$SERIAL" > "$STATE/identity"

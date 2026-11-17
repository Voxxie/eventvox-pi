#!/usr/bin/env bash
# De stap Raspberry Pi Connect van install.sh (setup_connect), zoals install.sh hem draait (set -euo pipefail):
# zonder auth key, met een leeg en met een gevuld connect-auth.key gaat de inrichting door. Zonder key brak hij eerder
# de hele eerste start af (v0.0.10). apt-cache, dpkg, systemctl en rpi-connect zijn nagebootst.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home"
for c in apt-cache dpkg systemctl; do printf '#!/bin/bash\nexit 0\n' > "$T/bin/$c"; done
printf '#!/bin/bash\necho "rpi-connect $*" >> "%s/calls"\n' "$T" > "$T/bin/rpi-connect"
chmod +x "$T/bin/"*
sed -n '/^setup_connect() {/,/^}/p' "$ROOT/install.sh" > "$T/fn.sh"
grep -q '^setup_connect() {' "$T/fn.sh" || { echo "FOUT: setup_connect niet gevonden in install.sh"; exit 1; }
run() {
  : > "$T/calls"
  PATH="$T/bin:$PATH" KEYDIR="$T" bash -c '
    set -euo pipefail
    KIOSK_USER=$(id -un); KIOSK_UID=$(id -u); KIOSK_HOME="$KEYDIR/home"
    as_user() { "$@"; }; chown() { :; }
    . "$KEYDIR/fn.sh"
    # connect-auth.key op de bootpartitie nagebootst: install.sh kijkt in /boot/firmware en /boot
    setup_connect_test() { sed "s#/boot/firmware/connect-auth.key /boot/connect-auth.key#$KEYDIR/connect-auth.key#" "$KEYDIR/fn.sh" > "$KEYDIR/fn2.sh"; . "$KEYDIR/fn2.sh"; setup_connect; }
    setup_connect_test
    echo VERDER'
}
fail() { echo "FOUT: $*"; exit 1; }
[ "$(run 2>/dev/null | tail -1)" = VERDER ] || fail "zonder auth key gaat de inrichting niet door"
echo "ok   zonder auth key: de inrichting gaat door"
: > "$T/connect-auth.key"
[ "$(run 2>/dev/null | tail -1)" = VERDER ] || fail "met een leeg connect-auth.key gaat de inrichting niet door"
echo "ok   leeg connect-auth.key: de inrichting gaat door"
printf 'rpuak_test\n' > "$T/connect-auth.key"
[ "$(run 2>/dev/null | tail -1)" = VERDER ] || fail "met een auth key gaat de inrichting niet door"
grep -q "rpi-connect signin --auth-key=rpuak_test" "$T/calls" || fail "auth key niet gebruikt: $(cat "$T/calls")"
[ -e "$T/connect-auth.key" ] && fail "connect-auth.key niet gewist"
echo "ok   met een auth key: gekoppeld en het bestand gewist"

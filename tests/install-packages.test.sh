#!/usr/bin/env bash
# installable() uit install.sh (welk pakket apt echt kan installeren), zoals install.sh hem draait (set -euo pipefail),
# met een nagebootste apt-cache: een pakket met een kandidaat, een dat alleen genoemd wordt (chromium-browser op
# Debian 13: "Candidate: (none)"), een onbekend pakket. Met een lange uitvoer na de kandidaat: een pijp naar grep -q gaf
# daar SIGPIPE en met pipefail leek elk pakket te ontbreken (de proef op een pc vond dat).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail() { echo "FOUT: $*"; exit 1; }
mkdir -p "$T/bin"
cat > "$T/bin/apt-cache" <<'EOF'
#!/bin/bash
[ "$1" = policy ] || exit 1
case "$2" in
  labwc) printf 'labwc:\n  Installed: (none)\n  Candidate: 0.8.4-1\n  Version table:\n'
         for i in $(seq 1 20000); do echo "     0.8.$i 500"; done ;;
  chromium-browser) printf 'chromium-browser:\n  Installed: (none)\n  Candidate: (none)\n  Version table:\n' ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$T/bin/apt-cache"
sed -n '/^installable() {/,/^}/p' "$ROOT/install.sh" > "$T/fn.sh"
grep -q '^installable() {' "$T/fn.sh" || fail "installable niet gevonden in install.sh"
check() { PATH="$T/bin:$PATH" bash -c 'set -euo pipefail; . "$1"; if installable "$2"; then echo ja; else echo nee; fi' _ "$T/fn.sh" "$1"; }
for i in 1 2 3; do [ "$(check labwc)" = ja ] || fail "labwc (met kandidaat) niet installeerbaar volgens installable (poging $i)"; done
echo "ok   pakket met een kandidaat: installeerbaar (ook met een lange uitvoer en pipefail)"
[ "$(check chromium-browser)" = nee ] || fail "chromium-browser zonder kandidaat toch installeerbaar"
echo "ok   alleen genoemd (Candidate: (none)): niet installeerbaar"
[ "$(check bestaat-niet)" = nee ] || fail "onbekend pakket toch installeerbaar"
echo "ok   onbekend pakket: niet installeerbaar"

# Het adres: de standaard, of een eigen URL= precies zoals gegeven (eerder kwam er een } achter een eigen adres)
LINES="$(grep -E '^(DEFAULT_URL=|URL="\$\{URL:-)' "$ROOT/install.sh")"
[ "$(printf '%s\n' "$LINES" | wc -l)" = 2 ] || fail "regels voor het adres niet gevonden in install.sh"
url() { env -u URL ${1:+URL="$1"} bash -c "$LINES"'; printf %s "$URL"'; }
[ "$(url)" = 'https://eventvox.nl/scanterminal/?serial={serial}' ] || fail "standaardadres: $(url)"
[ "$(url 'https://eigen.example/scan/?serial={serial}')" = 'https://eigen.example/scan/?serial={serial}' ] || fail "eigen adres veranderd: $(url 'https://eigen.example/scan/?serial={serial}')"
echo "ok   adres: de standaard, en een eigen URL= precies zoals gegeven"

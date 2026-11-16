#!/usr/bin/env bash
# ssh.py zonder Pi: de sleutels uit EventVOX komen in een eigen blok van authorized_keys; een sleutel uit Imager blijft;
# een ongeldige regel (opties, verkeerd type, geen base64) wordt overgeslagen; een lege lijst haalt alleen het blok weg.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export EVX_PI_STATE="$T" EVX_PI_SSH_HOME="$T/home"
mkdir -p "$T/home/.ssh"
fail() { echo "FOUT: $*"; cat "$T/home/.ssh/authorized_keys" 2>/dev/null; exit 1; }
IMAGER='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJtTHYaIO5796aiOoZU1uJc6fle3ed05wSHs0kqFvkQX hans@imager'
KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFoHZFVa9sx/pABql+KY2/5u+XxycAQKk+P814wP5jo eventvox:Hans_laptop_'
echo "$IMAGER" > "$T/home/.ssh/authorized_keys"
python3 - "$KEY" <<'PY' | python3 "$ROOT/pi/ssh.py" >/dev/null
import json, sys
print(json.dumps({'version': '0123456789abcdef', 'keys': [sys.argv[1],
    'command="rm -rf /" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFoHZFVa9sx/pABql+KY2/5u+XxycAQKk+P814wP5jo x',
    'ssh-rsa AAAAC3NzaC1lZDI1NTE5AAAAIGFoHZFVa9sx/pABql+KY2/5u+XxycAQKk+P814wP5jo x', 'ssh-ed25519 geen-base64! x']}))
PY
F="$T/home/.ssh/authorized_keys"
grep -qxF "$IMAGER" "$F" || fail "sleutel uit Imager weg"
grep -qxF "$KEY" "$F" || fail "sleutel uit EventVOX niet gezet"
grep -q 'command=' "$F" && fail "sleutel met opties gezet"
[ "$(grep -c '^ssh-' "$F")" = 2 ] || fail "ongeldige sleutels gezet"
[ "$(stat -c %a "$F")" = 600 ] || fail "rechten niet 600"
grep -q '"result": "1 sleutel (Hans_laptop_), 3 ongeldig"' "$T/ssh-result.json" || fail "uitkomst: $(cat "$T/ssh-result.json")"
echo "ok   sleutel gezet in een eigen blok, Imager-sleutel blijft, opties/verkeerd type/geen base64 overgeslagen"

echo '{"version":"fedcba9876543210","keys":[]}' | python3 "$ROOT/pi/ssh.py" >/dev/null
[ "$(cat "$F")" = "$IMAGER" ] || fail "lege lijst: niet alleen het blok weggehaald"
echo "ok   lege lijst: alleen de sleutels uit EventVOX weg"

if echo '{"version":"x","keys":[]}' | python3 "$ROOT/pi/ssh.py" 2>/dev/null; then fail "ongeldige versie geaccepteerd"; fi
echo "ok   ongeldige invoer geweigerd"

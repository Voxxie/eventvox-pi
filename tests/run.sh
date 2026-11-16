#!/usr/bin/env bash
# Alle controles die zonder Pi kunnen (lokaal en in CI): scripts, Python en de agent tegen Chromium.
# Met FRONTEND=/pad/naar/eventvox-frontend ook tegen de echte scanterminal.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "== Scripts"
for f in "$ROOT/install.sh" "$ROOT"/pi/*.sh "$ROOT/pi/eventvox-pi-root"; do bash -n "$f"; done
if command -v shellcheck >/dev/null; then
  shellcheck -S warning "$ROOT/install.sh" "$ROOT"/pi/*.sh "$ROOT/pi/eventvox-pi-root"
else
  echo "(shellcheck niet geïnstalleerd: overgeslagen)"
fi
echo "== Python"
python3 -m py_compile "$ROOT/pi/agent.py" "$ROOT/pi/wifi.py"
node --check "$ROOT/pi/bridge.js"
node --check "$ROOT/pi/locate.js"
echo "== Bijwerken (update.sh)"
bash "$ROOT/tests/update.test.sh"
echo "== Wifi (wifi.py)"
bash "$ROOT/tests/wifi.test.sh"
echo "== Agent tegen Chromium"
node --test "$ROOT/tests/agent.test.mjs"

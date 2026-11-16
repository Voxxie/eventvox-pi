#!/usr/bin/env bash
# wifi.py zonder Pi (nagebootste nmcli): netwerken uit EventVOX worden NetworkManager-verbindingen "evx-…", oude evx-
# verbindingen verdwijnen, andere (uit Imager) nooit; ongeldige invoer wordt overgeslagen of geweigerd; het wachtwoord
# staat niet in de uitkomst.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export FAKE_NM="$T" NMCLI="$ROOT/tests/fake-nmcli" EVX_PI_STATE="$T"
fail() { echo "FOUT: $*"; cat "$T/calls"; exit 1; }
printf 'preconfigured\nevx-0000000000\n' > "$T/cons"   # een netwerk uit Imager en een oud netwerk uit EventVOX

echo '{"version":"0123456789abcdef","networks":[
  {"ssid":"EventVOX-Scan","security":"WPA","password":"scan-wachtwoord-1","hidden":true,"priority":50},
  {"ssid":"Gast","security":"OPEN","password":"","hidden":false,"priority":0},
  {"ssid":"Fout\nnaam","security":"WPA","password":"geheim-123"}]}' | python3 "$ROOT/pi/wifi.py" >/dev/null
grep -q "^connection|add|type|wifi|con-name|evx-[0-9a-f]*|ifname|wlan0|ssid|EventVOX-Scan|connection.autoconnect|yes|connection.autoconnect-priority|50|wifi.hidden|yes|wifi-sec.key-mgmt|wpa-psk|wifi-sec.psk|scan-wachtwoord-1$" "$T/calls" || fail "WPA-netwerk niet goed toegevoegd"
grep -q "|ssid|Gast|" "$T/calls" || fail "open netwerk niet toegevoegd"
grep -q "Gast.*wifi-sec" "$T/calls" && fail "open netwerk met beveiliging"
grep -q "^connection|delete|evx-0000000000$" "$T/calls" || fail "oud EventVOX-netwerk niet verwijderd"
grep -q "delete|preconfigured" "$T/calls" && fail "netwerk uit Imager verwijderd"
RESULT="$(cat "$T/wifi-result.json")"
grep -q '"version": "0123456789abcdef"' <<<"$RESULT" || fail "versie niet bewaard: $RESULT"
grep -q "2 ingesteld, 1 verwijderd, 1 ongeldig" <<<"$RESULT" || fail "uitkomst: $RESULT"
grep -q "wachtwoord" <<<"$RESULT" && fail "wachtwoord in de uitkomst"
echo "ok   netwerken gezet, oud EventVOX-netwerk weg, Imager-netwerk blijft ($(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["result"])' "$T/wifi-result.json"))"

: > "$T/calls"
echo '{"version":"fedcba9876543210","networks":[]}' | python3 "$ROOT/pi/wifi.py" >/dev/null
grep -c "^connection|delete|evx-" "$T/calls" | grep -qx 2 || fail "lege lijst: niet beide EventVOX-netwerken verwijderd"
grep -q "delete|preconfigured" "$T/calls" && fail "lege lijst: netwerk uit Imager verwijderd"
echo "ok   lege lijst: alleen de netwerken uit EventVOX weg"

: > "$T/calls"
if echo '{"version":"x; rm -rf /","networks":[]}' | python3 "$ROOT/pi/wifi.py" 2>/dev/null; then fail "ongeldige versie geaccepteerd"; fi
[ -s "$T/calls" ] && fail "nmcli aangeroepen bij ongeldige invoer"
echo "ok   ongeldige invoer: geweigerd, nmcli niet aangeroepen"

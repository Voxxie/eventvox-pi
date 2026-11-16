#!/bin/bash
# Bijwerken (als root, eventvox-pi-update.service): eerst EventVOX-Pi zelf, dan Raspberry Pi OS en Chromium (apt).
# De nieuwste versie staat als update.json bij de GitHub-releases van Voxxie/eventvox-pi, in hetzelfde formaat
# als de kiosk-app: { versionCode, versionName, url, sha256, notes }. Kanaal "stable" of "beta" (instelling uit EventVOX).
# Is er iets nieuws geïnstalleerd, dan herstart de Pi. De uitkomst gaat met de status naar EventVOX (update-result.json).
set -uo pipefail
STATE="${EVX_PI_STATE:-/var/lib/eventvox-pi}"
OPT="${EVX_PI_OPT:-/opt/eventvox-pi}"
REPO="Voxxie/eventvox-pi"
# shellcheck disable=SC1090,SC1091
[ -r "${EVX_PI_CONFIG:-/etc/eventvox-pi/config}" ] && . "${EVX_PI_CONFIG:-/etc/eventvox-pi/config}"
CHANNEL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("settings",{}).get("update_channel","stable"))' "$STATE/state.json" 2>/dev/null || echo stable)"
if [ -n "${UPDATE_INDEX:-}" ]; then
  INDEX="$UPDATE_INDEX"  # een eigen plek (config), of een test
elif [ "$CHANNEL" = "beta" ]; then
  INDEX="https://github.com/$REPO/releases/download/beta/update.json"
else
  INDEX="https://github.com/$REPO/releases/latest/download/update.json"
fi

result() {
  python3 - "$STATE/update-result.json" "$1" <<'PY'
import datetime, json, sys
json.dump({'checked_at': datetime.datetime.now().astimezone().isoformat(timespec='seconds'), 'result': sys.argv[2]}, open(sys.argv[1], 'w'))
PY
  chown --reference="$STATE" "$STATE/update-result.json" 2>/dev/null || true
  echo "$1"
}

field() { python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1], ""))' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
MINE="$(cat "$OPT/VERSION_CODE" 2>/dev/null || echo 0)"
KIT=""
FAILED=""
if curl -fsSL --max-time 30 -o "$TMP/update.json" "$INDEX"; then
  CODE="$(field versionCode < "$TMP/update.json")"
  NAME="$(field versionName < "$TMP/update.json")"
  if [[ "$CODE" =~ ^[0-9]+$ ]] && [ "$CODE" -gt "$MINE" ]; then
    URL="$(field url < "$TMP/update.json")"
    SHA="$(field sha256 < "$TMP/update.json")"
    if curl -fsSL --max-time 300 -o "$TMP/kit.tar.gz" "$URL" && echo "$SHA  $TMP/kit.tar.gz" | sha256sum -c --quiet - \
        && tar -xzf "$TMP/kit.tar.gz" -C "$TMP" && [ -f "$TMP/eventvox-pi/install.sh" ] && bash "$TMP/eventvox-pi/install.sh" --update; then
      KIT="EventVOX-Pi $NAME"
    else
      FAILED="Bijwerken naar $NAME mislukt (download, controle of installatie)"
    fi
  fi
else
  FAILED="Controle mislukt: GitHub niet bereikbaar"
fi

# Raspberry Pi OS en Chromium
UPGRADED=0
if apt-get update -q >/dev/null 2>&1; then
  BEFORE="$(dpkg-query -W -f='${Package} ${Version}\n' | sha256sum)"
  DEBIAN_FRONTEND=noninteractive apt-get -y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade >/dev/null 2>&1
  [ "$(dpkg-query -W -f='${Package} ${Version}\n' | sha256sum)" != "$BEFORE" ] && UPGRADED=1
fi

if [ -n "$KIT" ] || [ "$UPGRADED" = 1 ]; then
  result "Bijgewerkt: ${KIT:-}${KIT:+, }$([ "$UPGRADED" = 1 ] && echo "systeempakketten" || echo "geen systeempakketten"); herstart"
  sleep 3
  systemctl reboot
elif [ -n "$FAILED" ]; then
  result "$FAILED"
else
  result "Actueel ($(cat "$OPT/VERSION" 2>/dev/null || echo onbekend))"
fi

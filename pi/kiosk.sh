#!/bin/bash
# Chromium als kiosk voor de EventVOX-scanterminal (gestart door labwc, als de kiosk-gebruiker).
# Opent het adres uit /etc/eventvox-pi/config met het serienummer van de Pi, en start Chromium opnieuw zodra hij stopt.
# De debugpoort (alleen 127.0.0.1) is voor de agent (agent.py): die zet de koppeling met EventVOX in de pagina.
STATE=/var/lib/eventvox-pi
URL_TEMPLATE="https://eventvox.nl/scanterminal/?serial={serial}"
# shellcheck disable=SC1091
[ -r /etc/eventvox-pi/config ] && . /etc/eventvox-pi/config
URL_TEMPLATE="${URL:-$URL_TEMPLATE}"
BROWSER="$(command -v chromium-browser || command -v chromium)"
PROFILE="$HOME/.config/eventvox-kiosk"
mkdir -p "$PROFILE"
# De cache van Chromium in het geheugen (/run/user, tmpfs) in plaats van op de SD-kaart: minder schrijven. De opslag van
# de scanterminal (koppeling, offline gegevens) blijft in het profiel op de kaart. Een oude cache op de kaart weg.
CACHE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/eventvox-cache"
mkdir -p "$CACHE" 2>/dev/null || CACHE="$PROFILE/cache"
rm -rf "$PROFILE/Default/Cache" "$PROFILE/Default/Code Cache" 2>/dev/null

# labwc verbergt de cursor niet vanzelf: na 15 s stilte naar de hoek (Raspberry Pi Connect laat hem anders midden staan)
command -v swayidle >/dev/null && command -v wlrctl >/dev/null && swayidle -w timeout 15 'wlrctl pointer move 10000 10000' &

# Geluid via HDMI. Met de KMS-videodriver van Raspberry Pi OS is HDMI-geluid een eigen geluidskaart (vc4hdmi, op een Pi 4/5
# vc4hdmi0 en vc4hdmi1) en is de standaardkaart de koptelefoonaansluiting; Chromium gebruikt de standaard (ALSA). Daarom
# bij elke start de standaard op de HDMI-kaart zetten: de eerste met een aangesloten scherm, anders de eerste HDMI-kaart.
# HDMI_AUDIO=0 in /etc/eventvox-pi/config laat het geluid zoals het is (bijvoorbeeld een USB-luidspreker).
if [ "${HDMI_AUDIO:-1}" != "0" ]; then
  CARD=""
  for status in /sys/class/drm/card*-HDMI-A-*/status; do
    [ "$(cat "$status" 2>/dev/null)" = "connected" ] || continue
    PORT="${status%/status}"; PORT="${PORT##*-HDMI-A-}"   # 1 of 2
    for id in "vc4hdmi$((PORT - 1))" vc4hdmi; do grep -q "\[$id *\]" /proc/asound/cards 2>/dev/null && { CARD="$id"; break; }; done
    [ -n "$CARD" ] && break
  done
  [ -z "$CARD" ] && CARD="$(grep -o '\[vc4hdmi[0-9]* *\]' /proc/asound/cards 2>/dev/null | head -1 | tr -d '[] ')"
  if [ -n "$CARD" ]; then
    cat > "$HOME/.asoundrc" <<EOF
# Door EventVOX-Pi (kiosk.sh) bij elke start gezet: geluid via HDMI ($CARD)
pcm.!default { type plug slave.pcm "hdmi:CARD=$CARD,DEV=0" }
ctl.!default { type hw card $CARD }
EOF
  fi
fi

# Wacht op netwerk (hoogstens 30 s): anders eerst een foutpagina na een snelle start
for _ in $(seq 1 30); do
  getent hosts eventvox.nl >/dev/null 2>&1 && break
  sleep 1
done

while true; do
  SERIAL="$(grep -m1 '^Serial' /proc/cpuinfo | awk '{print $3}' | sed 's/^0*//')"
  PAGE="${URL_TEMPLATE//\{serial\}/$SERIAL}"
  # Geen "Chromium is niet goed afgesloten"-balk: een kiosk wordt nooit netjes uitgezet
  sed -i 's/"exited_cleanly":false/"exited_cleanly":true/; s/"exit_type":"Crashed"/"exit_type":"Normal"/' \
    "$PROFILE/Default/Preferences" 2>/dev/null || true

  "$BROWSER" \
    --kiosk \
    --ozone-platform=wayland \
    --user-data-dir="$PROFILE" \
    --remote-debugging-port=9222 \
    --noerrdialogs \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --disable-translate \
    --disable-features=TranslateUI \
    --no-first-run \
    --check-for-update-interval=31536000 \
    --disable-component-update \
    --disk-cache-dir="$CACHE" \
    --disk-cache-size=33554432 \
    --disable-pinch \
    --overscroll-history-navigation=0 \
    --autoplay-policy=no-user-gesture-required \
    "$PAGE"

  # Een herstart die EventVOX of de nacht vroeg telt niet als crash
  if [ -f "$STATE/restart-requested" ]; then
    rm -f "$STATE/restart-requested"
  else
    date +%s >> "$STATE/browser-exits"
    tail -n 50 "$STATE/browser-exits" > "$STATE/browser-exits.tmp" 2>/dev/null && mv "$STATE/browser-exits.tmp" "$STATE/browser-exits"
  fi
  sleep 2
done

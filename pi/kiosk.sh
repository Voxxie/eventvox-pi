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

# labwc verbergt de cursor niet vanzelf: na 15 s stilte naar de hoek (Raspberry Pi Connect laat hem anders midden staan)
command -v swayidle >/dev/null && command -v wlrctl >/dev/null && swayidle -w timeout 15 'wlrctl pointer move 10000 10000' &

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

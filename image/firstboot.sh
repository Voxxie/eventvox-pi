#!/bin/bash
# EventVOX-Pi, eerste start van het image: wacht tot er een gebruiker is (uit Raspberry Pi Imager, of aangemaakt op het
# scherm van de eerste start), richt dan de kiosk in met de meegeleverde install.sh (alles staat al op de kaart, er is
# geen netwerk nodig) en herstart één keer. Daarna toont het scherm de koppelcode van EventVOX.
# Op het scherm (onder het logo) staat intussen wat hij doet, hoe lang al en het IP-adres: zo zie je dat hij niet hangt.
LOG="${EVX_FIRSTBOOT_LOG:-/var/log/eventvox-pi-firstboot.log}"
TTY="${EVX_FIRSTBOOT_TTY:-/dev/tty1}"
KIT="${EVX_FIRSTBOOT_KIT:-/opt/eventvox-pi-kit}"
NOW="$(mktemp -d)"
exec >>"$LOG" 2>&1
echo "== $(date) eerste start"
START=$(date +%s)
TOTAL=$(grep -c '^ *step "' "$KIT/install.sh" 2>/dev/null || echo 0)
echo "Opstarten" > "$NOW/step"
echo 0 > "$NOW/n"

# Twee regels onderaan het scherm, over het logo heen; de rest van het scherm blijft staan
show() {
  { printf '\033[?25l\033[999;1H\033[2A\033[J'; printf '  %s\n  %s' "$1" "$2"; } >> "$TTY" 2>/dev/null || true
}
info() {
  local min ip
  min=$(( ($(date +%s) - START) / 60 ))
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  printf '%s min bezig%s · niet uitzetten' "$min" "${ip:+ · IP $ip}"
}
ticker() {
  while true; do
    local n step
    n="$(cat "$NOW/n" 2>/dev/null)"; step="$(cat "$NOW/step" 2>/dev/null)"
    if [ "${n:-0}" -gt 0 ]; then
      show "EventVOX-Pi wordt ingericht: stap $n van ongeveer $TOTAL, $step" "$(info)"
    else
      show "EventVOX-Pi: $step" "$(info)"
    fi
    sleep 5
  done
}
ticker &
TICKER=$!
stop_ticker() { kill "$TICKER" 2>/dev/null; wait "$TICKER" 2>/dev/null; }

WAITED=0
until getent passwd 1000 >/dev/null; do
  if [ "$WAITED" -ge 600 ]; then
    echo "Wachten op een gebruiker. Zet in Raspberry Pi Imager bij Instellingen een gebruikersnaam en wachtwoord" > "$NOW/step"
  else
    echo "wachten op de instellingen uit Raspberry Pi Imager (gebruiker)" > "$NOW/step"
  fi
  sleep 5; WAITED=$((WAITED + 5))
done
# cloud-init (Imager) kan de gebruiker net aanmaken: even wachten tot alles klaar is
echo "instellingen uit Raspberry Pi Imager afronden" > "$NOW/step"
sleep 5

# install.sh meldt elke stap als "==> tekst": die gaat naar het scherm, alles gaat naar het logboek
bash "$KIT/install.sh" --firstboot 2>&1 | while IFS= read -r line; do
  printf '%s\n' "$line"
  case "$line" in
    "==> "*) echo $(( $(cat "$NOW/n") + 1 )) > "$NOW/n"; printf '%s' "${line#==> }" | cut -c1-70 > "$NOW/step" ;;
  esac
done
STATUS=${PIPESTATUS[0]}
stop_ticker

if [ "$STATUS" = 0 ]; then
  [ -z "${EVX_FIRSTBOOT_DRYRUN:-}" ] && systemctl disable eventvox-pi-firstboot.service
  [ -z "${EVX_FIRSTBOOT_DRYRUN:-}" ] && rm -rf "$KIT"
  echo "== klaar, herstart"
  show "EventVOX-Pi is ingericht. De Pi herstart en toont daarna de koppelcode." "$(info)"
  sleep 3
  if [ -z "${EVX_FIRSTBOOT_DRYRUN:-}" ]; then systemctl reboot; fi
else
  echo "== install.sh mislukt; volgende start opnieuw (zie dit logboek)"
  show "Inrichten mislukt bij: $(cat "$NOW/step"). Herstart de Pi om het opnieuw te proberen." \
    "Logboek: $LOG$(ip="$(hostname -I 2>/dev/null | awk '{print $1}')"; [ -n "$ip" ] && printf ' · IP %s' "$ip")"
fi
rm -rf "$NOW"

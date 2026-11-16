#!/bin/bash
# EventVOX-Pi, eerste start van het image: wacht tot er een gebruiker is (uit Raspberry Pi Imager, of aangemaakt op het
# scherm van de eerste start), richt dan de kiosk in met de meegeleverde install.sh (alles staat al op de kaart, er is
# geen netwerk nodig) en herstart één keer. Daarna toont het scherm de koppelcode van EventVOX.
LOG=/var/log/eventvox-pi-firstboot.log
exec >>"$LOG" 2>&1
echo "== $(date) eerste start"
until getent passwd 1000 >/dev/null; do sleep 5; done
# cloud-init (Imager) kan de gebruiker net aanmaken: even wachten tot alles klaar is
sleep 5
if bash /opt/eventvox-pi-kit/install.sh --firstboot; then
  systemctl disable eventvox-pi-firstboot.service
  rm -rf /opt/eventvox-pi-kit
  echo "== klaar, herstart"
  systemctl reboot
else
  echo "== install.sh mislukt; volgende start opnieuw (zie dit logboek)"
fi

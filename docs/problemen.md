# Problemen oplossen

Log in via SSH of Raspberry Pi Connect (*Remote shell*).

| Probleem | Wat te doen |
|---|---|
| **Zwart scherm** | `journalctl --user -u eventvox-pi-agent -n 50` en `cat /var/lib/eventvox-pi/log.txt`. Start de kiosk opnieuw met `sudo reboot`. |
| **"Geen verbinding" op het scherm** | Netwerk controleren: `ping eventvox.nl`. Wifi: `nmcli device wifi list`. |
| **De Pi verschijnt niet in EventVOX** | Staat er een code op het scherm? Koppel hem dan (Toegang → Terminals → Terminal koppelen). |
| **Opdrachten uit EventVOX doen niets** | Draait de agent? `systemctl --user status eventvox-pi-agent`. Het logboek: `cat /var/lib/eventvox-pi/log.txt`. |
| **Bijwerken lukt niet** | `cat /var/lib/eventvox-pi/update-result.json`, en met de hand: `sudo systemctl start eventvox-pi-update`. |
| **Connect koppelt niet** | De auth key is verlopen of al gebruikt. Koppel met de hand: `rpi-connect signin` (als de kiosk-gebruiker). |
| **SSH vraagt om een wachtwoord** | Staat je publieke sleutel in EventVOX (Alle terminals → SSH-sleutels) en toont de kaart van de terminal *SSH-sleutels* met jouw naam? Log in als de gebruiker uit Imager. Anders: het wachtwoord uit Imager, of Raspberry Pi Connect. |
| **Geen geluid** | Het geluid gaat via HDMI: staat het scherm niet op stil? |

Het logboek kun je ook vanuit EventVOX opvragen: **Diagnose opvragen** op de pagina van de terminal.

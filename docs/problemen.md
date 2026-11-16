# Problemen oplossen

Log in via SSH of Raspberry Pi Connect (*Remote shell*).

| Probleem | Wat te doen |
|---|---|
| **Weinig vrije ruimte, of de totale grootte is veel kleiner dan de SD-kaart** | De Diagnose toont de SD-kaart en het laatste *Onderhoud*. Is de kaart niet vergroot (totaal veel kleiner dan de kaart): `sudo raspi-config`, *Advanced Options*, *Expand Filesystem*, en herstarten. Opruimen kan ook meteen: `sudo /opt/eventvox-pi/cleanup.sh`. |
| **Traag of haperend** | Kijk eerst naar de voeding: meldt de Pi onderspanning, dan remt hij zichzelf af. Gebruik een goede voeding (Pi 3: 5,1 V / 2,5 A) en een korte kabel. |
| **Zwart scherm** | `journalctl --user -u eventvox-pi-agent -n 50` en `cat /var/lib/eventvox-pi/log.txt`. Start de kiosk opnieuw met `sudo reboot`. |
| **"Geen verbinding" op het scherm** | Netwerk controleren: `ping eventvox.nl`. Wifi: `nmcli device wifi list`. |
| **De Pi verschijnt niet in EventVOX** | Staat er een code op het scherm? Koppel hem dan (Toegang → Terminals → Terminal koppelen). |
| **Opdrachten uit EventVOX doen niets** | Draait de agent? `systemctl --user status eventvox-pi-agent`. Het logboek: `cat /var/lib/eventvox-pi/log.txt`. |
| **Bijwerken lukt niet** | `cat /var/lib/eventvox-pi/update-result.json`, en met de hand: `sudo systemctl start eventvox-pi-update`. |
| **Connect koppelt niet** | De auth key is verlopen of al gebruikt. Koppel met de hand: `rpi-connect signin` (als de kiosk-gebruiker). |
| **SSH vraagt om een wachtwoord** | Staat je publieke sleutel in EventVOX (Alle terminals → SSH-sleutels) en toont de kaart van de terminal *SSH-sleutels* met jouw naam? Log in als de gebruiker uit Imager. Anders: het wachtwoord uit Imager, of Raspberry Pi Connect. |
| **NFC-lezer piept, maar er gebeurt niets** | Werkt de barcodescanner wel? Een lezer die als toetsenbord typt (werkt hij op een gewone computer in Kladblok?) heeft NumLock nodig; dat zet EventVOX-Pi aan in `~/.config/labwc/rc.xml` (na *Nu bijwerken* en een herstart). Een gewone kaartlezer (zoals de ACR122U) leest EventVOX-Pi zelf uit: kijk in `cat /var/lib/eventvox-pi/log.txt` of er *NFC-kaart gelezen* staat, en met `pcsc_scan` (pakket pcsc-tools) of de lezer gezien wordt. Staat er *pyscard ontbreekt* of *PC/SC niet bereikbaar*: werk de Pi bij (*Nu bijwerken*). |
| **Geen geluid** | Het geluid gaat via HDMI naar het scherm: heeft het scherm luidsprekers en staat het niet op stil? Bij elke start kiest de Pi de HDMI-geluidskaart van het aangesloten scherm (`cat ~/.asoundrc`). Testen: `speaker-test -c2 -t sine -l1`. Een USB-luidspreker gebruiken: zet `HDMI_AUDIO=0` in `/etc/eventvox-pi/config`. |
| **Zwart scherm tijdens het opstarten, geen logo** | Het logo komt alleen met het image of een nieuwe installatie (niet bij bijwerken). Kijk of het er staat: `ls -l /lib/firmware/logo.tga`, en of in `/boot/firmware/cmdline.txt` `fullscreen_logo=1` staat en géén `logo.nologo`. |
| **Pi start niet meer op na bijwerken naar v0.0.6** (zwart scherm, geen SSH) | v0.0.6 stelde bij bijwerken het opstartlogo in en bouwde daarvoor de initramfs opnieuw; vanaf v0.0.7 niet meer. Herstel: SD-kaart in een computer, op de partitie *bootfs*: in `config.txt` `auto_initramfs=1` veranderen in `auto_initramfs=0` (de Pi start dan zonder initramfs), en in `cmdline.txt` `quiet loglevel=1` en `fullscreen_logo=1 fullscreen_logo_name=logo.tga vt.global_cursor_default=0` weghalen en `console=tty1` toevoegen (alles op één regel), zodat je ziet wat er gebeurt. Start de Pi weer, dan via SSH `sudo update-initramfs -u -k all` en `auto_initramfs=1` terugzetten. |

Het logboek kun je ook vanuit EventVOX opvragen: **Diagnose opvragen** op de pagina van de terminal.

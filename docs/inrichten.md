# Een Pi inrichten

## Wat je nodig hebt

- Een Raspberry Pi 3B of nieuwer, met de officiële voeding
- Een SD-kaart (8 GB of meer)
- Een scherm via HDMI (het geluid van de scanterminal gaat via HDMI) en een USB-scanner
- Netwerk: een kabel of wifi

## 1. SD-kaart flashen

Open **Raspberry Pi Imager** op je computer:

1. Kies je Pi en als besturingssysteem **Raspberry Pi OS Lite** (onder *Raspberry Pi OS (other)*), Bookworm of nieuwer.
2. Bij de instellingen (*Edit settings*):
   - een **gebruikersnaam en wachtwoord** (de kiosk draait als deze gebruiker);
   - het **wifi-netwerk** en land **NL** (niet nodig met een kabel);
   - bij *Services*: **SSH aan**;
   - optioneel **Raspberry Pi Connect** (Imager 2.0.10 of nieuwer): plak een auth key, zie hieronder.
3. Schrijf de kaart.

## 2. Raspberry Pi Connect (optioneel, aanbevolen)

Met [Raspberry Pi Connect](https://connect.raspberrypi.com) kijk je op afstand mee op het scherm van de Pi en open je
een terminal, zonder dat je in hetzelfde netwerk zit. Koppelen gaat met een **auth key**, zodat je per Pi niet hoeft in te
loggen:

1. Log in op connect.raspberrypi.com en maak een auth key (*Add device* → *auth key*).
2. Geef de key mee op één van deze manieren:
   - in Raspberry Pi Imager (stap 1);
   - als bestand `connect-auth.key` op de bootpartitie van de SD-kaart (die zie je op je computer na het flashen); het
     script gebruikt de key en wist het bestand daarna;
   - bij het installeren: `sudo CONNECT_AUTH_KEY=rpuak_… bash install.sh`.

Een **persoonlijk** account heeft maar één key tegelijk en die verloopt na **6 uur**: maak hem vlak voor het inrichten,
en voor elke Pi een nieuwe. Met *Connect for Organisations* kun je meerdere keys tegelijk maken (1 tot 90 dagen geldig).

Zonder key kun je later koppelen met `rpi-connect signin` (als de kiosk-gebruiker).

## 3. Installeren

Start de Pi en log in via SSH (`ssh <gebruiker>@<hostname>.local`) of met een toetsenbord op de Pi:

```bash
curl -fsSLO https://github.com/Voxxie/eventvox-pi/releases/latest/download/install.sh
sudo bash install.sh
sudo reboot
```

Het script haalt zelf de nieuwste versie op. Het duurt een paar minuten (Chromium installeren).

### Opties

Zet ze vóór `bash`, bijvoorbeeld `sudo URL=https://… bash install.sh`:

| Optie | Wat |
|---|---|
| `CONNECT_AUTH_KEY=rpuak_…` | Raspberry Pi Connect koppelen (zie stap 2) |
| `URL=https://…{serial}` | Een ander adres dan `https://eventvox.nl/scanterminal/?serial={serial}`; `{serial}` wordt het serienummer |
| `WIFI_SSID=… WIFI_PASSWORD=…` | Een (extra) wifi-netwerk, als je dat niet in Imager deed |
| `KIOSK_USER=…` | De gebruiker van de kiosk; standaard die uit Imager |

## 4. Koppelen in EventVOX

Na de herstart toont het scherm een **code van 6 tekens**. Ga in EventVOX naar **Toegang → Terminals → Terminal
koppelen**, typ de code over, geef de terminal een naam en kies waar hij scant. Klaar: vanaf nu zie je hem in EventVOX
en kun je hem bedienen ([bediening](bediening.md)).

## Meer Pi's

Doe stap 1–4 per Pi. Elke Pi krijgt vanzelf een eigen naam (`eventvox-<serienummer>`) en, in EventVOX, een eigen code.

# Een Pi inrichten

## Wat je nodig hebt

- Een Raspberry Pi 3B of nieuwer, met de officiële voeding
- Een SD-kaart (8 GB of meer)
- Een scherm via HDMI (het geluid van de scanterminal gaat via HDMI) en een USB-scanner
- Optioneel een USB-NFC-lezer voor polsbandjes (zie [bediening](bediening.md#nfc-lezer))
- Netwerk: een kabel of wifi

## Twee manieren

- **Het EventVOX-Pi-image (aanbevolen):** flashen met Raspberry Pi Imager, de Pi aanzetten, klaar. Geen SSH nodig.
- **Het installatiescript:** eerst gewoon Raspberry Pi OS, dan via SSH één commando (zie onderaan). Handig voor een Pi
  die al draait.

## Met het EventVOX-Pi-image

### Eenmalig: EventVOX-Pi in Raspberry Pi Imager zetten

Je hebt **Raspberry Pi Imager 2** nodig (raspberrypi.com/software). Kies één van:

- download `eventvox-pi.rpi-imager-manifest` bij de
  [nieuwste release](https://github.com/Voxxie/eventvox-pi/releases/latest) en dubbelklik erop; of
- in Imager: **App Options → Content Repository → EDIT → Use custom URL** met
  `https://github.com/Voxxie/eventvox-pi/releases/latest/download/eventvox-pi.json`, dan **APPLY & RESTART**.

Download het `.img.xz`-bestand niet los om te openen met *Use custom*: dan weet Imager niet hoe hij je instellingen
(gebruiker, wifi) moet toepassen en slaat hij ze over.

### Flashen

1. Kies je Pi en dan **EventVOX-Pi** als besturingssysteem, en je SD-kaart.
2. Bij de instellingen:
   - een **gebruikersnaam en wachtwoord** (de kiosk draait als deze gebruiker);
   - het **wifi-netwerk** en land **NL** (niet nodig met een kabel; netwerken uit EventVOX komen er later vanzelf bij);
   - **SSH aan** (handig voor onderhoud);
   - **Raspberry Pi Connect**: plak een auth key (zie hieronder).
3. Schrijf de kaart, zet hem in de Pi en zet de Pi aan.

De Pi start, richt de kiosk in en herstart één keer. Op een Pi 3 duurt dat ongeveer 5 tot 10 minuten (de eerste start
vergroot ook de kaart en verwerkt de instellingen uit Imager). Onderaan het scherm staat intussen wat hij doet: de stap
("stap 6 van ongeveer 14, …"), hoe lang hij al bezig is en het IP-adres. Zolang de minuten oplopen, is hij bezig: niet
uitzetten. Daarna staat er een **code van 6 tekens** op het scherm: ga verder bij
[Koppelen in EventVOX](#4-koppelen-in-eventvox).

Staat er *Inrichten mislukt*, herstart de Pi dan: hij probeert het opnieuw. Het logboek staat in
`/var/log/eventvox-pi-firstboot.log` (via SSH).

Bijwerken gaat daarna vanzelf (zie [bijwerken](bijwerken-en-releases.md)); je hoeft een Pi niet opnieuw te flashen
voor een nieuwe versie.

## Met het installatiescript

### 1. SD-kaart flashen

Open **Raspberry Pi Imager** op je computer:

1. Kies je Pi en als besturingssysteem **Raspberry Pi OS Lite** (onder *Raspberry Pi OS (other)*), Bookworm of nieuwer.
2. Bij de instellingen (*Edit settings*):
   - een **gebruikersnaam en wachtwoord** (de kiosk draait als deze gebruiker);
   - het **wifi-netwerk** en land **NL** (niet nodig met een kabel);
   - bij *Services*: **SSH aan**;
   - optioneel **Raspberry Pi Connect** (Imager 2.0.10 of nieuwer): plak een auth key, zie hieronder.
3. Schrijf de kaart.

### 2. Raspberry Pi Connect (optioneel; kan ook later vanuit EventVOX)

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

Zonder key koppel je later vanuit EventVOX: *Koppelen met Connect* op de pagina van de terminal (zie
[bediening](bediening.md#raspberry-pi-connect-koppelen-vanuit-eventvox)), of met `rpi-connect signin` (als de kiosk-gebruiker).

### 3. Installeren

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

### 4. Koppelen in EventVOX

Na de herstart toont het scherm een **code van 6 tekens**. Ga in EventVOX naar **Toegang → Terminals → Terminal
koppelen**, typ de code over, geef de terminal een naam en kies waar hij scant. Klaar: vanaf nu zie je hem in EventVOX
en kun je hem bedienen ([bediening](bediening.md)).

## Meer Pi's

Doe stap 1–4 per Pi. Elke Pi krijgt vanzelf een eigen naam (`eventvox-<serienummer>`) en, in EventVOX, een eigen code.

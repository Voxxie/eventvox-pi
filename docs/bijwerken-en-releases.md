# Bijwerken en releases

## Hoe een Pi bijwerkt

- **EventVOX-Pi bijwerken** in EventVOX: alleen EventVOX-Pi zelf (seconden). Is er een nieuwe versie, dan starten de
  agent en de browser opnieuw; de Pi zelf herstart niet. Handig vlak voor of tijdens een evenement.
- **Alles bijwerken** in EventVOX: EventVOX-Pi én de updates van Raspberry Pi OS en Chromium (op een Pi 3 soms 5 tot 20
  minuten). Was er iets nieuws, dan herstart de Pi.
- **'s Nachts** (instelling *Automatisch bijwerken*): **standaard uit** (vanaf 0.0.13). Aan: rond 4:00, na 5 minuten
  zonder scans, hetzelfde als *Alles bijwerken*.
- **Beveiligingsupdates** komen daarnaast elke dag automatisch (unattended-upgrades).

Een nieuwe EventVOX-Pi wordt gecontroleerd (SHA-256) voordat hij wordt geïnstalleerd. Elke oudere versie kan meteen naar
de nieuwste, zonder tussenstappen; de instellingen blijven.

## Kanalen

| Kanaal | Krijgt | Instellen |
|---|---|---|
| **Stabiel** | De nieuwste gewone release | Standaard |
| **Test** | Ook pre-releases | EventVOX → Kiosk-instellingen → Kanaal: Test |

Zet één of twee Pi's op het testkanaal om een nieuwe versie eerst te proberen.

## Een nieuwe versie uitbrengen

1. Zorg dat de controle op `main` groen is (Actions → *Controle*).
2. Maak een **release** op GitHub met een nieuwe tag `vMAJOR.MINOR.PATCH`, bijvoorbeeld `v1.0.1`.
   - MINOR en PATCH zijn 0–99; elke nieuwe tag is hoger dan de vorige. Hergebruik nooit een tag.
   - Eerst testen? Vink **Set as a pre-release** aan: alleen Pi's op het testkanaal krijgen hem. Werkt hij, haal het
     vinkje weg (of maak een gewone release).
3. GitHub Actions (*Release EventVOX-Pi*) hangt binnen een paar minuten aan de release:
   - `eventvox-pi-<versie>.tar.gz` (het pakket: `install.sh` en `pi/`)
   - `install.sh` (voor het installatiecommando)
   - `update.json` (wat de Pi's lezen)
   - na ongeveer een half uur ook het image (`eventvox-pi-<versie>.img.xz`) en de beschrijving voor Raspberry Pi
     Imager (`eventvox-pi.json`, `eventvox-pi.rpi-imager-manifest`), via *Image EventVOX-Pi*

   en werkt de pre-release **beta** bij (het testkanaal; geen versie, niet installeren).

`update.json` staat altijd op dezelfde plek:

- stabiel: `https://github.com/Voxxie/eventvox-pi/releases/latest/download/update.json`
- test: `https://github.com/Voxxie/eventvox-pi/releases/download/beta/update.json`

EventVOX haalt de nieuwste versie elk uur op en markeert oudere Pi's in de terminallijst.

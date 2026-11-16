#!/bin/bash
# ---------------------------------------------------------------------------------------------------------------------
# EventVOX-Pi: maakt van een Raspberry Pi (3B of nieuwer, Raspberry Pi OS Lite Bookworm) een EventVOX-scanterminal.
#
#   curl -fsSLO https://github.com/Voxxie/eventvox-pi/releases/latest/download/install.sh
#   sudo bash install.sh            eerste keer (na het flashen met Raspberry Pi Imager)
#   sudo bash install.sh --update   door de Pi zelf bij het bijwerken (update.sh): bestanden vernieuwen, instellingen houden
#   install.sh --firstboot          door het EventVOX-Pi-image bij de eerste start (image/firstboot.sh)
#
# Optioneel, alleen bij de eerste keer (nooit in dit bestand zetten, het staat in git):
#   CONNECT_AUTH_KEY=rpuak_...      Raspberry Pi Connect koppelen zonder inloggen (of: connect-auth.key op de bootpartitie)
#   WIFI_SSID=... WIFI_PASSWORD=... een (extra) wifi-netwerk; liever via Raspberry Pi Imager
#   URL=https://...{serial}         een ander adres dan https://eventvox.nl/scanterminal/?serial={serial}
#   KIOSK_USER=...                  standaard de eerste gebruiker (uid 1000), zoals ingesteld in Imager
#
# Zie README.md en docs/. Wat het doet: labwc (Wayland) + Chromium als kiosk op de scanterminal, geen popups, geluid via HDMI,
# een eigen hostname per Pi, de agent die EventVOX de Pi laat zien en bedienen, bijwerken via GitHub, automatische
# beveiligingsupdates en Raspberry Pi Connect (op afstand meekijken).
# ---------------------------------------------------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")"

# Los gedownload (alleen install.sh): eerst het hele pakket van de nieuwste release halen en dat installeren
if [ ! -d pi ]; then
  REPO="Voxxie/eventvox-pi"
  TMP="$(mktemp -d)"
  echo "==> Nieuwste EventVOX-Pi downloaden"
  curl -fsSL -o "$TMP/update.json" "https://github.com/$REPO/releases/latest/download/update.json"
  PKG_URL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["url"])' "$TMP/update.json")"
  PKG_SHA="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha256"])' "$TMP/update.json")"
  curl -fsSL -o "$TMP/kit.tar.gz" "$PKG_URL"
  echo "$PKG_SHA  $TMP/kit.tar.gz" | sha256sum -c --quiet -
  tar -xzf "$TMP/kit.tar.gz" -C "$TMP"
  exec bash "$TMP/eventvox-pi/install.sh" "$@"
fi

UPDATE=0
FIRSTBOOT=0
[ "${1:-}" = "--update" ] && UPDATE=1
# --firstboot: vanuit het EventVOX-Pi-image bij de eerste start (image/firstboot.sh): alles staat al op de kaart
[ "${1:-}" = "--firstboot" ] && FIRSTBOOT=1
if [ "$(id -u)" -ne 0 ]; then
  echo "Draai dit met sudo: sudo bash install.sh" >&2
  exit 1
fi

OPT=/opt/eventvox-pi
STATE=/var/lib/eventvox-pi
CONF_DIR=/etc/eventvox-pi
CONF="$CONF_DIR/config"

# De kiosk-gebruiker: uit de config (bij bijwerken), anders KIOSK_USER of de eerste gewone gebruiker
# shellcheck disable=SC1090
[ -r "$CONF" ] && . "$CONF"
KIOSK_USER="${KIOSK_USER:-$(getent passwd 1000 | cut -d: -f1)}"
URL="${URL:-https://eventvox.nl/scanterminal/?serial={serial}}"
KIOSK_HOME="$(getent passwd "$KIOSK_USER" | cut -d: -f6)"
if [ -z "$KIOSK_USER" ] || [ ! -d "$KIOSK_HOME" ]; then
  echo "Geen kiosk-gebruiker gevonden. Maak er een in Raspberry Pi Imager, of geef KIOSK_USER=naam mee." >&2
  exit 1
fi
KIOSK_UID="$(id -u "$KIOSK_USER")"
# raspi-config kiest zijn gebruiker uit SUDO_USER (bij de eerste start van het image is er geen sudo)
export SUDO_USER="${SUDO_USER:-$KIOSK_USER}"
as_user() { sudo -u "$KIOSK_USER" XDG_RUNTIME_DIR="/run/user/$KIOSK_UID" "$@"; }
step() { echo "==> $*"; }

# --- pakketten ----------------------------------------------------------------------------------------------------------

PACKAGES="labwc seatd swayidle wlrctl fonts-liberation python3 iw curl unattended-upgrades"
if apt-cache show chromium-browser >/dev/null 2>&1; then PACKAGES="$PACKAGES chromium-browser"; else PACKAGES="$PACKAGES chromium"; fi
MISSING=""
for p in $PACKAGES; do dpkg -s "$p" >/dev/null 2>&1 || MISSING="$MISSING $p"; done
if [ -n "$MISSING" ]; then
  step "Pakketten installeren:$MISSING"
  apt-get update -q
  # shellcheck disable=SC2086
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends $MISSING
fi

# --- EventVOX-Pi zelf -----------------------------------------------------------------------------------------------------

step "EventVOX-Pi $(cat pi/VERSION) installeren in $OPT"
mkdir -p "$OPT" "$CONF_DIR" "$STATE"
install -m 0755 pi/agent.py pi/kiosk.sh pi/update.sh pi/wifi.py "$OPT/"
install -m 0644 pi/bridge.js pi/locate.js pi/VERSION pi/VERSION_CODE "$OPT/"
install -m 0755 -o root -g root pi/eventvox-pi-root /usr/local/sbin/eventvox-pi-root
chown "$KIOSK_USER:$KIOSK_USER" "$STATE"
if [ ! -f "$CONF" ]; then
  cat > "$CONF" <<EOF
# EventVOX-Pi (zie /opt/eventvox-pi en https://github.com/Voxxie/eventvox-pi)
KIOSK_USER=$KIOSK_USER
# Het adres; {serial} wordt het serienummer van de Pi
URL=$URL
EOF
fi

# Herstarten, bijwerken en wifi zetten mag de agent als root, alleen deze drie
cat > /etc/sudoers.d/eventvox-pi <<EOF
$KIOSK_USER ALL=(root) NOPASSWD: /usr/local/sbin/eventvox-pi-root reboot, /usr/local/sbin/eventvox-pi-root update, /usr/local/sbin/eventvox-pi-root wifi
EOF
chmod 0440 /etc/sudoers.d/eventvox-pi
visudo -cf /etc/sudoers.d/eventvox-pi >/dev/null

cat > /etc/systemd/system/eventvox-pi-update.service <<'EOF'
[Unit]
Description=EventVOX-Pi en Raspberry Pi OS bijwerken
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/eventvox-pi/update.sh
TimeoutStartSec=3600
EOF

# De agent als gebruikersdienst (draait ook zonder ingelogde sessie dankzij linger)
cat > /etc/systemd/user/eventvox-pi-agent.service <<'EOF'
[Unit]
Description=EventVOX-Pi agent (koppeling tussen de scanterminal en de Pi)

[Service]
ExecStart=/usr/bin/python3 /opt/eventvox-pi/agent.py
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF
systemctl daemon-reload
systemctl --global enable eventvox-pi-agent.service >/dev/null 2>&1 || true
loginctl enable-linger "$KIOSK_USER"

if [ "$UPDATE" = 1 ]; then
  step "Bijgewerkt; de Pi herstart (update.sh)"
  exit 0
fi

# --- alleen bij de eerste keer: de kiosk zelf ----------------------------------------------------------------------------

step "seatd: labwc mag het scherm en de invoer gebruiken zonder desktop"
systemctl enable --now seatd
usermod -aG seat,video,input,render,audio "$KIOSK_USER" || true

step "Wifi-land NL"
raspi-config nonint do_wifi_country NL < /dev/null || true
if [ -n "${WIFI_SSID:-}" ] && command -v nmcli >/dev/null 2>&1; then
  step "Wifi-netwerk ${WIFI_SSID} toevoegen"
  nmcli connection delete "eventvox-wifi" >/dev/null 2>&1 || true
  nmcli connection add type wifi con-name "eventvox-wifi" ifname wlan0 ssid "$WIFI_SSID" \
    wifi-sec.key-mgmt wpa-psk wifi-sec.psk "${WIFI_PASSWORD:-}" connection.autoconnect yes >/dev/null
fi

step "Chromium-policy: geen vertaalbalk, geen inlog- of standaardbrowser-vragen"
for dir in /etc/chromium-browser/policies/managed /etc/chromium/policies/managed; do
  mkdir -p "$dir"
  cat > "$dir/eventvox-pi.json" <<'EOF'
{ "TranslateEnabled": false, "DefaultBrowserSettingEnabled": false, "BrowserSignin": 0, "SyncDisabled": true,
  "PasswordManagerEnabled": false, "AutofillAddressEnabled": false, "AutofillCreditCardEnabled": false }
EOF
done

step "Automatisch inloggen op tty1, labwc en de kiosk starten"
raspi-config nonint do_boot_behaviour B2 < /dev/null
cat > "$KIOSK_HOME/.bash_profile" <<'EOF'
# EventVOX-Pi: op het scherm (tty1) meteen labwc met de kiosk; via SSH een gewone shell
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  exec labwc
fi
EOF
mkdir -p "$KIOSK_HOME/.config/labwc"
cat > "$KIOSK_HOME/.config/labwc/autostart" <<'EOF'
/opt/eventvox-pi/kiosk.sh &
EOF
chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.bash_profile" "$KIOSK_HOME/.config"

step "Opstartscherm rustig, scherm nooit uit, geluid via HDMI"
CONFIG_TXT=/boot/firmware/config.txt; [ -f "$CONFIG_TXT" ] || CONFIG_TXT=/boot/config.txt
CMDLINE_TXT=/boot/firmware/cmdline.txt; [ -f "$CMDLINE_TXT" ] || CMDLINE_TXT=/boot/cmdline.txt
for line in disable_splash=1 dtoverlay=vc4-kms-v3d avoid_warnings=1 dtparam=audio=on; do
  grep -q "^$line" "$CONFIG_TXT" || echo "$line" >> "$CONFIG_TXT"
done
for key in hdmi_drive=2 hdmi_group=1; do
  if grep -q "^${key%%=*}=" "$CONFIG_TXT"; then sed -i "s/^${key%%=*}=.*/$key/" "$CONFIG_TXT"; else echo "$key" >> "$CONFIG_TXT"; fi
done
grep -q " quiet" "$CMDLINE_TXT" || sed -i 's/$/ quiet loglevel=1 logo.nologo/' "$CMDLINE_TXT"
grep -q "consoleblank=" "$CMDLINE_TXT" || sed -i 's/$/ consoleblank=0/' "$CMDLINE_TXT"
amixer cset numid=3 2 >/dev/null 2>&1 < /dev/null || true
alsactl store >/dev/null 2>&1 || true

step "Eigen hostname per Pi (eventvox-<serienummer>), ook na het klonen van een kaart"
cat > /usr/local/sbin/eventvox-pi-identity <<'EOF'
#!/bin/bash
# Eigen naam en SSH-sleutels per Pi. Bij de eerste keer: de naam uit Raspberry Pi Imager blijft, alleen de standaardnaam
# raspberrypi wordt eventvox-<serienummer>. Op een gekloonde SD-kaart (ander serienummer dan de vorige keer): een eigen
# naam en nieuwe SSH-sleutels, zodat niet alle Pi's hetzelfde op het netwerk staan.
SERIAL="$(grep -m1 '^Serial' /proc/cpuinfo | awk '{print $3}' | tail -c 9)"
PREVIOUS="$(cat /var/lib/eventvox-pi/identity 2>/dev/null)"
[ "$PREVIOUS" = "$SERIAL" ] && exit 0
if [ -n "$PREVIOUS" ]; then
  raspi-config nonint do_hostname "eventvox-$SERIAL" < /dev/null
  rm -f /etc/ssh/ssh_host_*
  ssh-keygen -A
elif [ "$(hostname)" = "raspberrypi" ]; then
  raspi-config nonint do_hostname "eventvox-$SERIAL" < /dev/null
fi
echo "$SERIAL" > /var/lib/eventvox-pi/identity
EOF
chmod 0755 /usr/local/sbin/eventvox-pi-identity
cat > /etc/systemd/system/eventvox-pi-identity.service <<'EOF'
[Unit]
Description=EventVOX-Pi: eigen hostname en SSH-sleutels per Pi
Before=ssh.service
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/eventvox-pi-identity
RemainAfterExit=yes
TimeoutStartSec=20

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable eventvox-pi-identity.service >/dev/null
/usr/local/sbin/eventvox-pi-identity || true

step "Automatische beveiligingsupdates (Debian en Raspberry Pi OS)"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# --- Raspberry Pi Connect -----------------------------------------------------------------------------------------------

step "Raspberry Pi Connect (op afstand meekijken en een terminal)"
# De gebruikersdiensten draaien (linger), ook zonder dat er al iemand ingelogd is (eerste start van het image)
systemctl start "user@$KIOSK_UID.service" >/dev/null 2>&1 || true
if apt-cache show rpi-connect >/dev/null 2>&1; then
  dpkg -s rpi-connect >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y -q rpi-connect
  as_user rpi-connect on >/dev/null 2>&1 || true
  as_user systemctl --user enable rpi-connect.service >/dev/null 2>&1 || true
  # Een auth key (Connect, "Add device" > auth key): de Pi koppelt zichzelf, zonder in te loggen in een browser.
  # Uit CONNECT_AUTH_KEY of het bestand connect-auth.key op de bootpartitie (dat daarna gewist wordt: de bootpartitie
  # kan iedereen met de SD-kaart lezen).
  KEY_FILE=""
  for f in /boot/firmware/connect-auth.key /boot/connect-auth.key; do [ -f "$f" ] && KEY_FILE="$f"; done
  KEY="${CONNECT_AUTH_KEY:-$( [ -n "$KEY_FILE" ] && tr -d ' \r\n' < "$KEY_FILE")}"
  if [ -n "$KEY" ]; then
    mkdir -p "$KIOSK_HOME/.config/com.raspberrypi.connect"
    printf '%s' "$KEY" > "$KIOSK_HOME/.config/com.raspberrypi.connect/auth.key"
    chmod 0600 "$KIOSK_HOME/.config/com.raspberrypi.connect/auth.key"
    chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.config/com.raspberrypi.connect"
    # Connect vindt auth.key ook zelf bij het starten; lukt het nu meteen, dan is het bestand niet meer nodig
    if as_user rpi-connect signin --auth-key="$KEY"; then
      echo "    Gekoppeld aan Raspberry Pi Connect."
      rm -f "$KIOSK_HOME/.config/com.raspberrypi.connect/auth.key"
    else
      echo "    Nu koppelen lukte niet; Connect probeert het na de herstart met auth.key. Anders: rpi-connect signin" >&2
    fi
    [ -n "$KEY_FILE" ] && rm -f "$KEY_FILE"
  else
    echo "    Geen auth key: koppel later met  sudo -u $KIOSK_USER XDG_RUNTIME_DIR=/run/user/$KIOSK_UID rpi-connect signin"
  fi
else
  echo "    rpi-connect niet beschikbaar (Raspberry Pi OS Bookworm of nieuwer nodig); overgeslagen."
fi

echo ""
if [ "$FIRSTBOOT" = 1 ]; then
  echo "==> Klaar (eerste start van het image)"
  exit 0
fi
echo "==> Klaar. Herstart met:  sudo reboot"
echo "    Daarna toont het scherm een code: koppel de terminal in EventVOX (Toegang > Terminals > Terminal koppelen)."

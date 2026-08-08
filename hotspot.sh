#!/usr/bin/env bash
set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "[*] Elevating permissions..."
  exec sudo bash -c "$(curl -sSL https://wifi.kodliebe.me)" -- "$@"
fi

has_cmd() {
  command -v "$1" &>/dev/null
}

if ! (has_cmd hostapd && has_cmd dnsmasq && has_cmd iptables && has_cmd iw && has_cmd git && has_cmd python3); then
    echo "[*] Missing dependencies detected. Installing..."
    if has_cmd apt-get; then
        apt-get update -y || true
        apt-get install -y hostapd dnsmasq iptables iproute2 iw git build-essential python3
    elif has_cmd dnf; then
        dnf install -y hostapd dnsmasq iptables iproute2 iw git make gcc python3
    elif has_cmd pacman; then
        pacman -Sy --needed --noconfirm hostapd dnsmasq iptables iproute2 iw git make gcc python
    elif has_cmd zypper; then
        zypper install -y hostapd dnsmasq iptables iproute2 iw git make gcc python3
    else
        echo "[!] Unsupported package manager. Install dependencies manually."
        exit 1
    fi
fi

if ! has_cmd create_ap; then
    echo "[*] create_ap not found. Building CLI from source..."
    TMP_DIR=$(mktemp -d)
    git clone --depth 1 https://github.com/lakinduakash/linux-wifi-hotspot.git "$TMP_DIR"
    cd "$TMP_DIR"
    make build_gui=0
    make install build_gui=0
    cd - > /dev/null
    rm -rf "$TMP_DIR"
fi

WIFI_IFACE=$(iw dev | awk '$1=="Interface"{print $2}' | head -n1)

if [ -z "$WIFI_IFACE" ]; then
    echo "[!] No active Wi-Fi interface detected."
    exit 1
fi

FREQ=$(iw dev "$WIFI_IFACE" link | awk '/freq:/{print $2}')

if [ -z "$FREQ" ]; then
    FREQ=$(iw dev "$WIFI_IFACE" info | awk '/channel/{print $2}' | tr -d '()MHz,')
fi

if [ -n "$FREQ" ]; then
    CHANNEL=$(python3 -c "
freq = int(float('$FREQ'))
if 2412 <= freq <= 2484:
    print(int((freq - 2407) / 5))
elif 5170 <= freq <= 5825:
    print(int((freq - 5000) / 5))
else
    print('')
" 2>/dev/null || true)
fi

CHANNEL=${CHANNEL:-6}

echo "------------------------------------------"
read -r -p "Enter SSID: " SSID </dev/tty
read -r -p "Enter Hotspot Password (min 8 chars): " PASSPHRASE </dev/tty
echo "------------------------------------------"

if [ -z "$SSID" ] || [ -z "$PASSPHRASE" ]; then
    echo "[!] SSID and Password cannot be empty."
    exit 1
fi

echo "=========================================="
echo " Starting Concurrent AP-STA Hotspot"
echo " Interface : $WIFI_IFACE"
echo " Channel   : $CHANNEL"
echo " SSID      : $SSID"
echo " Password  : $PASSPHRASE"
echo "=========================================="

create_ap "$WIFI_IFACE" "$WIFI_IFACE" "$SSID" "$PASSPHRASE" -c "$CHANNEL"

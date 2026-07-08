#!/bin/sh
echo "Content-Type: application/json"
echo ""

LOG_FILE="/tmp/join_wifi.log"

echo "[$(date)] Script started" >> "$LOG_FILE"

INPUT=$(cat | tr -d '\r')
echo "[$(date)] Received JSON: $INPUT" >> "$LOG_FILE"

DEVICE=$(echo "$INPUT" | jsonfilter -e '@.device')
SSID=$(echo "$INPUT" | jsonfilter -e '@.ssid')
BSSID=$(echo "$INPUT" | jsonfilter -e '@.bssid')
CHANNEL=$(echo "$INPUT" | jsonfilter -e '@.channel')
ENCRYPTION=$(echo "$INPUT" | jsonfilter -e '@.encryption')
PASSWORD=$(echo "$INPUT" | jsonfilter -e '@.password')

echo "[$(date)] Parsed - DEVICE: $DEVICE, SSID: $SSID, BSSID: $BSSID, CHANNEL: $CHANNEL, ENCRYPTION: $ENCRYPTION" >> "$LOG_FILE"

if [ -z "$DEVICE" ] || [ -z "$SSID" ] || [ -z "$BSSID" ]; then
    echo "[$(date)] Error: Missing DEVICE, SSID, or BSSID" >> "$LOG_FILE"
    echo '{"status":"error", "message":"Missing DEVICE, SSID, or BSSID"}'
    exit 1
fi

# Create new wifi-iface section
SECTION=$(uci add wireless wifi-iface)
echo "[$(date)] Created section: $SECTION" >> "$LOG_FILE"

uci set wireless.$SECTION.device="$DEVICE"
uci set wireless.$SECTION.mode='sta'
uci set wireless.$SECTION.network='wwan'
uci set wireless.$SECTION.ssid="$SSID"
uci set wireless.$SECTION.bssid="$BSSID"

if [ "$ENCRYPTION" = "Open" ]; then
    uci set wireless.$SECTION.encryption="none"
    echo "[$(date)] Open network, no key required" >> "$LOG_FILE"
elif echo "$ENCRYPTION" | grep -q "mixed WPA/WPA2 PSK (TKIP, CCMP)"; then
    uci set wireless.$SECTION.encryption="psk2+tkip+ccmp"
    uci set wireless.$SECTION.key="$PASSWORD"
    echo "[$(date)] mixed WPA/WPA2 PSK (TKIP, CCMP) set" >> "$LOG_FILE"
elif echo "$ENCRYPTION" | grep -q "WPA3"; then
    uci set wireless.$SECTION.encryption="sae"
    uci set wireless.$SECTION.key="$PASSWORD"
    uci set wireless.$SECTION.ieee80211w=2
    echo "[$(date)] WPA3-SAE set" >> "$LOG_FILE"
elif echo "$ENCRYPTION" | grep -q "WPA2"; then
    uci set wireless.$SECTION.encryption="psk2"
    uci set wireless.$SECTION.key="$PASSWORD"
    echo "[$(date)] WPA2-PSK set" >> "$LOG_FILE"
elif echo "$ENCRYPTION" | grep -q "WPA1"; then
    uci set wireless.$SECTION.encryption="psk"
    uci set wireless.$SECTION.key="$PASSWORD"
    echo "[$(date)] WPA1-PSK set" >> "$LOG_FILE"
else
    echo "[$(date)] Error: Unsupported encryption type: $ENCRYPTION" >> "$LOG_FILE"
    echo '{"status":"error", "message":"Unsupported encryption type"}'
    exit 1
fi

if [ -n "$CHANNEL" ]; then
    uci set wireless.$DEVICE.channel="$CHANNEL"
fi

net=$(uci get wireless.$SECTION.network)
net_iface=$(uci get network.$net)

if [ -n "$net_iface" ]; then
    uci set network.$net=interface
    uci set network.$net.proto='dhcp'
    uci commit network
    /etc/init.d/network reload
fi

echo "[$(date)] UCI committed. Restarting Wi-Fi..." >> "$LOG_FILE"

echo '{"success": true}'

uci commit wireless
wifi

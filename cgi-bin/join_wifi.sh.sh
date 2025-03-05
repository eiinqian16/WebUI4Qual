#!/bin/sh
echo "Content-Type: text/plain"
echo ""

LOG_FILE="/tmp/join_wifi.log"

echo "[$(date)] Script started" >> "$LOG_FILE"

INPUT=$(cat)
echo "[$(date)] Received JSON: $INPUT" >> "$LOG_FILE"

DEVICE=$(echo "$INPUT" | jsonfilter -e '@.device')
SSID=$(echo "$INPUT" | jsonfilter -e '@.ssid')
BSSID=$(echo "$INPUT" | jsonfilter -e '@.bssid')
CHANNEL=$(echo "$INPUT" | jsonfilter -e '@.channel')
ENCRYPTION=$(echo "$INPUT" | jsonfilter -e '@.encryption')
PASSWORD=$(echo "$INPUT" | jsonfilter -e '@.password')

echo "[$(date)] Parsed - DEVICE: $DEVICE, BSSID: $BSSID, SSID: $SSID, CHANNEL: $CHANNEL, ENCRYPTION: $ENCRYPTION" >> "$LOG_FILE"

if [ -z "$DEVICE" ] || [ -z "$SSID" ]; then
    echo "[$(date)] Error: Missing DEVICE or SSID" >> "$LOG_FILE"
    exit 1
fi

MAX_IFACE_INDEX=$(uci show wireless | grep -o "wireless.@wifi-iface\[[0-9]\+\]" | grep -o "[0-9]\+" | sort -nr | head -n 1)
if [ -z "$MAX_IFACE_INDEX" ]; then
    MAX_IFACE_INDEX=-1
fi
NEW_IFACE_INDEX=$((MAX_IFACE_INDEX + 1))

NEW_IFACE=$(uci add wireless wifi-iface)
if [ -z "$NEW_IFACE" ]; then
    echo "[$(date)] Error: uci add failed!" >> "$LOG_FILE"
    exit 1
fi
IFACE_NAME="@wifi-iface[$NEW_IFACE_INDEX]"
echo "[$(date)] Created new iface: $IFACE_NAME" >> "$LOG_FILE"

uci set wireless.$IFACE_NAME.device="$DEVICE"
uci set wireless.$IFACE_NAME.network="wwan"
uci set wireless.$IFACE_NAME.mode="sta"
uci set wireless.$IFACE_NAME.ssid="$SSID"
uci set wireless.$IFACE_NAME.bssid="$BSSID"

if [ "$ENCRYPTION" = "Open" ]; then
    uci set wireless.$IFACE_NAME.encryption="none"
    uci -q delete wireless.$IFACE_NAME.key
    echo "[$(date)] Open network, no key required" >> "$LOG_FILE"
elif echo "$ENCRYPTION" | grep -q "WPA3"; then
    uci set wireless.$IFACE_NAME.encryption="sae"
    uci set wireless.$IFACE_NAME.key="$PASSWORD"
    echo "[$(date)] WPA3-SAE set" >> "$LOG_FILE"
elif echo "$ENCRYPTION" | grep -q "WPA2"; then
    uci set wireless.$IFACE_NAME.encryption="psk2"
    uci set wireless.$IFACE_NAME.key="$PASSWORD"
    echo "[$(date)] WPA2-PSK set" >> "$LOG_FILE"
elif echo "$ENCRYPTION" | grep -q "WPA1"; then
    uci set wireless.$IFACE_NAME.encryption="psk"
    uci set wireless.$IFACE_NAME.key="$PASSWORD"
    echo "[$(date)] WPA1-PSK set" >> "$LOG_FILE"
else
    echo "[$(date)] Error: Unsupported encryption type: $ENCRYPTION" >> "$LOG_FILE"
    exit 1
fi

if [ -n "$CHANNEL" ]; then
    uci set wireless.$DEVICE.channel="$CHANNEL"
fi

uci commit wireless

echo "[$(date)] UCI committed. Restarting Wi-Fi..." >> "$LOG_FILE"
wifi reload

echo "[$(date)] Wi-Fi join process completed" >> "$LOG_FILE"
echo ""
echo '{"status":"success", "message":"Wi-Fi Join successful"}'


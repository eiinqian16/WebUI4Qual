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

# ✅ 先检查是否已有相同 BSSID 的 iface
EXISTING_IFACE=$(uci show wireless | grep -E "wireless.@wifi-iface\[[0-9]+\].bssid='$BSSID'" | awk -F'=' '{print $1}')

if [ -n "$EXISTING_IFACE" ]; then
    echo "[$(date)] Found existing iface for BSSID $BSSID: $EXISTING_IFACE" >> "$LOG_FILE"
else
    echo "[$(date)] No existing iface found. Creating a new one..." >> "$LOG_FILE"

    MAX_IFACE_INDEX=$(uci show wireless | grep -o "wireless.@wifi-iface\[[0-9]\+\]" | grep -o "[0-9]\+" | sort -nr | head -n 1)
    if [ -z "$MAX_IFACE_INDEX" ]; then
        MAX_IFACE_INDEX=-1
    fi
    NEW_IFACE_INDEX=$((MAX_IFACE_INDEX + 1))
    NEW_IFACE=$(uci add wireless wifi-iface)
    if [ -z "$NEW_IFACE" ]; then
        echo "[$(date)] Error: uci add failed!" >> "$LOG_FILE"
        echo '{"status":"error", "message":"uci add failed"}'
        exit 1
    fi
    EXISTING_IFACE="wireless.@wifi-iface[$NEW_IFACE_INDEX]"
fi

# ✅ 更新已有的 iface 或新创建的 iface
uci set $EXISTING_IFACE.device="$DEVICE"
uci set $EXISTING_IFACE.network="wwan"
uci set $EXISTING_IFACE.mode="sta"
uci set $EXISTING_IFACE.ssid="$SSID"
uci set $EXISTING_IFACE.bssid="$BSSID"

if [ "$ENCRYPTION" = "Open" ]; then
    uci set $EXISTING_IFACE.encryption="none"
    uci -q delete $EXISTING_IFACE.key
    echo "[$(date)] Open network, no key required" >> "$LOG_FILE"
elif echo "$ENCRYPTION" | grep -q "WPA3"; then
    uci set $EXISTING_IFACE.encryption="sae"
    uci set $EXISTING_IFACE.key="$PASSWORD"
    echo "[$(date)] WPA3-SAE set" >> "$LOG_FILE"
elif echo "$ENCRYPTION" | grep -q "WPA2"; then
    uci set $EXISTING_IFACE.encryption="psk2"
    uci set $EXISTING_IFACE.key="$PASSWORD"
    echo "[$(date)] WPA2-PSK set" >> "$LOG_FILE"
elif echo "$ENCRYPTION" | grep -q "WPA1"; then
    uci set $EXISTING_IFACE.encryption="psk"
    uci set $EXISTING_IFACE.key="$PASSWORD"
    echo "[$(date)] WPA1-PSK set" >> "$LOG_FILE"
else
    echo "[$(date)] Error: Unsupported encryption type: $ENCRYPTION" >> "$LOG_FILE"
    echo '{"status":"error", "message":"Unsupported encryption type"}'
    exit 1
fi

if [ -n "$CHANNEL" ]; then
    uci set wireless.$DEVICE.channel="$CHANNEL"
fi

uci commit wireless
wifi reload

echo "[$(date)] UCI committed. Restarting Wi-Fi..." >> "$LOG_FILE"

echo '{"success": true}'


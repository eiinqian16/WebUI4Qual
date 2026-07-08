#!/bin/sh
echo "Content-Type: text/plain"
echo ""

LOG_FILE="/tmp/wifi_config.log"

echo "---- New Request ----" >> $LOG_FILE
date >> $LOG_FILE

INPUT=$(cat)
echo "Input JSON: $INPUT" >> $LOG_FILE

DEVICE=$(echo "$INPUT" | jsonfilter -e '@.device')
CREATE_NEW=$(echo "$INPUT" | jsonfilter -e '@.create_new')
CHANNEL=$(echo "$INPUT" | jsonfilter -e '@.channel')
HWMODE=$(echo "$INPUT" | jsonfilter -e '@.hwmode')
HTMODE=$(echo "$INPUT" | jsonfilter -e '@.htmode')
DISABLED=$(echo "$INPUT" | jsonfilter -e '@.disabled')
TXPOWER=$(echo "$INPUT" | jsonfilter -e '@.txpower')
COUNTRY=$(echo "$INPUT" | jsonfilter -e '@.country')
BAND=$(echo "$INPUT" | jsonfilter -e '@.band')

IFACE_JSON=$(echo "$INPUT" | jsonfilter -e '@.iface')
IFACE_NAME=$(echo "$IFACE_JSON" | jsonfilter -e '@.iface')
IFACE_SSID=$(echo "$IFACE_JSON" | jsonfilter -e '@.ssid')
IFACE_MODE=$(echo "$IFACE_JSON" | jsonfilter -e '@.mode')
IFACE_ENCRYPTION=$(echo "$IFACE_JSON" | jsonfilter -e '@.encryption')
IFACE_SAE=$(echo "$IFACE_JSON" | jsonfilter -e '@.sae')
IFACE_KEY=$(echo "$IFACE_JSON" | jsonfilter -e '@.key')

echo "Parsed values:" >> $LOG_FILE
echo "DEVICE=$DEVICE" >> $LOG_FILE
echo "BAND=$BAND" >> $LOG_FILE
echo "HWMODE=$HWMODE" >> $LOG_FILE
echo "HTMODE=$HTMODE" >> $LOG_FILE
echo "SSID=$IFACE_SSID" >> $LOG_FILE
echo "MODE=$IFACE_MODE" >> $LOG_FILE
echo "ENCRYPTION=$IFACE_ENCRYPTION" >> $LOG_FILE
echo "KEY=********" >> $LOG_FILE
echo "CREATE_NEW=$CREATE_NEW" >> $LOG_FILE

# add new wifi-iface
SECTION=$(uci add wireless wifi-iface)
echo "[$(date)] Created section: $SECTION" >> "$LOG_FILE"

uci set wireless.$SECTION.device="$DEVICE"
uci set wireless.$SECTION.mode="$IFACE_MODE"
uci set wireless.$SECTION.ssid="$IFACE_SSID"

if [ "$IFACE_ENCRYPTION" == "none" ]; then
    uci set wireless.$SECTION.encryption="none"
    echo "[$(date)] Open network, no key required" >> "$LOG_FILE"
elif echo "$IFACE_ENCRYPTION" | grep -q "mixed WPA/WPA2 PSK (TKIP, CCMP)"; then
    uci set wireless.$SECTION.encryption="psk2+tkip+ccmp"
    uci set wireless.$SECTION.key="$PASSWORD"
    echo "[$(date)] mixed WPA/WPA2 PSK (TKIP, CCMP) set" >> "$LOG_FILE"
elif echo "$IFACE_ENCRYPTION" | grep -q "WPA3"; then
    uci set wireless.$SECTION.encryption="sae"
    uci set wireless.$SECTION.key="$PASSWORD"
    uci set wireless.$SECTION.ieee80211w=2
    echo "[$(date)] WPA3-SAE set" >> "$LOG_FILE"
elif echo "$IFACE_ENCRYPTION" | grep -q "WPA2"; then
    uci set wireless.$SECTION.encryption="psk2"
    uci set wireless.$SECTION.key="$PASSWORD"
    echo "[$(date)] WPA2-PSK set" >> "$LOG_FILE"
elif echo "$IFACE_ENCRYPTION" | grep -q "WPA1"; then
    uci set wireless.$SECTION.encryption="psk"
    uci set wireless.$SECTION.key="$PASSWORD"
    echo "[$(date)] WPA1-PSK set" >> "$LOG_FILE"
else
    echo "[$(date)] Error: Unsupported encryption type: $ENCRYPTION" >> "$LOG_FILE"
    echo '{"status":"error", "message":"Unsupported encryption type"}'
    exit 1
fi

uci set wireless.$DEVICE.hwmode="$HWMODE"

if [ -z "$HTMODE" ] || [ "$HTMODE" = "null" ]; then
    uci delete wireless.$DEVICE.htmode
    echo "HTMODE deleted for $DEVICE" >> $LOG_FILE
else
    uci set wireless.$DEVICE.htmode="$HTMODE"
fi

uci set wireless.$DEVICE.disabled="$DISABLED"

if [ -z "$CHANNEL" ] || [ "$CHANNEL" = "null" ]; then
    uci set wireless.$DEVICE.channel="auto"
else
    uci set wireless.$DEVICE.channel="$CHANNEL"
fi

if [ -z "$TXPOWER" ] || [ "$TXPOWER" = "null" ]; then
    uci delete wireless.$DEVICE.txpower
else
    uci set wireless.$DEVICE.txpower="$TXPOWER"
fi

if [ -z "$COUNTRY" ] || [ "$COUNTRY" = "null" ]; then
    uci delete wireless.$DEVICE.country 2>/dev/null
else
    uci set wireless.$DEVICE.country="$COUNTRY"
fi

echo "Checking UCI before commit:" >> $LOG_FILE
uci show wireless | grep "default_radio" >> $LOG_FILE

uci commit wireless
sleep 2

echo "Checking UCI after commit:" >> $LOG_FILE
uci show wireless | grep "default_radio" >> $LOG_FILE

echo "Configuration saved successfully"
echo "Wi-Fi Configuration for $DEVICE saved and applied." >> $LOG_FILE
uci show wireless >> $LOG_FILE

wifi
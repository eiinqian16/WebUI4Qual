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

IFACE_JSON=$(echo "$INPUT" | jsonfilter -e '@.iface')
IFACE_NAME=$(echo "$IFACE_JSON" | jsonfilter -e '@.iface')
IFACE_SSID=$(echo "$IFACE_JSON" | jsonfilter -e '@.ssid')
IFACE_MODE=$(echo "$IFACE_JSON" | jsonfilter -e '@.mode')
IFACE_ENCRYPTION=$(echo "$IFACE_JSON" | jsonfilter -e '@.encryption')
IFACE_KEY=$(echo "$IFACE_JSON" | jsonfilter -e '@.key')   

echo "Parsed values:" >> $LOG_FILE
echo "DEVICE=$DEVICE" >> $LOG_FILE
echo "HWMODE=$HWMODE" >> $LOG_FILE
echo "HTMODE=$HTMODE" >> $LOG_FILE
echo "SSID=$IFACE_SSID" >> $LOG_FILE
echo "MODE=$IFACE_MODE" >> $LOG_FILE
echo "ENCRYPTION=$IFACE_ENCRYPTION" >> $LOG_FILE
echo "KEY=********" >> $LOG_FILE
echo "CREATE_NEW=$CREATE_NEW" >> $LOG_FILE

if [ -z "$DEVICE" ]; then
    echo "Error: DEVICE is empty" >> $LOG_FILE
    exit 1
fi

if [ "$CREATE_NEW" = "true" ]; then
    MAX_IFACE_INDEX=$(uci show wireless | grep -o "wireless.@wifi-iface\[[0-9]\+\]" | grep -o "[0-9]\+" | sort -nr | head -n 1)
    if [ -z "$MAX_IFACE_INDEX" ]; then
        MAX_IFACE_INDEX=-1
    fi

    NEW_IFACE_INDEX=$((MAX_IFACE_INDEX + 1))
    echo "New iface index: $NEW_IFACE_INDEX" >> $LOG_FILE

    NEW_IFACE=$(uci add wireless wifi-iface)

    if [ -z "$NEW_IFACE" ]; then
        echo "Error: uci add failed!" >> $LOG_FILE
        exit 1
    fi

    echo "New iface added: $NEW_IFACE" >> $LOG_FILE
    IFACE_NAME="@wifi-iface[$NEW_IFACE_INDEX]"
else
    if [ -z "$IFACE_NAME" ]; then
        echo "Error: No iface provided for modification." >> $LOG_FILE
        exit 1
    fi

    echo "Modifying existing iface: $IFACE_NAME" >> $LOG_FILE
fi

uci set wireless.$IFACE_NAME.device="$DEVICE"
uci set wireless.$IFACE_NAME.network="lan"
uci set wireless.$IFACE_NAME.mode="$IFACE_MODE"
uci set wireless.$IFACE_NAME.ssid="$IFACE_SSID"
uci set wireless.$IFACE_NAME.encryption="$IFACE_ENCRYPTION"

if [ "$IFACE_ENCRYPTION" = "none" ]; then
    uci -q delete wireless.$IFACE_NAME.key
    echo "Encryption is none, deleted key" >> $LOG_FILE
elif [ -n "$IFACE_KEY" ]; then
    uci set wireless.$IFACE_NAME.key="$IFACE_KEY"
    echo "Encryption set, key applied" >> $LOG_FILE
fi

if [ "$IFACE_MODE" = "sta" ]; then
    uci set wireless.$IFACE_NAME.extap='1'
else
    uci -q delete wireless.$IFACE_NAME.extap
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

# **检查 UCI 变更前**
echo "Checking UCI before commit:" >> $LOG_FILE
uci show wireless | grep "@wifi-iface" >> $LOG_FILE

uci commit wireless
sleep 2

echo "Checking UCI after commit:" >> $LOG_FILE
uci show wireless | grep "@wifi-iface" >> $LOG_FILE

wifi reload

echo "Configuration saved successfully"
echo "Wi-Fi Configuration for $DEVICE saved and applied." >> $LOG_FILE
uci show wireless >> $LOG_FILE


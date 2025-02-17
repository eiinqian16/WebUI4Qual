echo "Content-Type: text/plain"
echo ""

LOG_FILE="/tmp/wifi_config.log"

echo "---- New Request ----" >> $LOG_FILE
date >> $LOG_FILE

INPUT=$(cat)
echo "Input JSON: $INPUT" >> $LOG_FILE

DEVICE=$(echo "$INPUT" | jsonfilter -e '@.device')
TYPE=$(echo "$INPUT" | jsonfilter -e '@.type')
CHANNEL=$(echo "$INPUT" | jsonfilter -e '@.channel')
MACADDR=$(echo "$INPUT" | jsonfilter -e '@.macaddr')
HWMODE=$(echo "$INPUT" | jsonfilter -e '@.hwmode')
DISABLED=$(echo "$INPUT" | jsonfilter -e '@.disabled')
IFACE_DEVICE=$(echo "$INPUT" | jsonfilter -e '@.iface.device')
IFACE_NETWORK=$(echo "$INPUT" | jsonfilter -e '@.iface.network')
IFACE_MODE=$(echo "$INPUT" | jsonfilter -e '@.iface.mode')
IFACE_SSID=$(echo "$INPUT" | jsonfilter -e '@.iface.ssid')
IFACE_ENCRYPTION=$(echo "$INPUT" | jsonfilter -e '@.iface.encryption')

echo "Parsed Variables:" >> $LOG_FILE
echo "DEVICE: $DEVICE" >> $LOG_FILE
echo "TYPE: $TYPE" >> $LOG_FILE
echo "CHANNEL: $CHANNEL" >> $LOG_FILE
echo "MACADDR: $MACADDR" >> $LOG_FILE
echo "HWMODE: $HWMODE" >> $LOG_FILE
echo "DISABLED: $DISABLED" >> $LOG_FILE
echo "IFACE_DEVICE: $IFACE_DEVICE" >> $LOG_FILE
echo "IFACE_NETWORK: $IFACE_NETWORK" >> $LOG_FILE
echo "IFACE_MODE: $IFACE_MODE" >> $LOG_FILE
echo "IFACE_SSID: $IFACE_SSID" >> $LOG_FILE
echo "IFACE_ENCRYPTION: $IFACE_ENCRYPTION" >> $LOG_FILE

if [ -z "$DEVICE" ]; then
    echo "Error: DEVICE is empty" >> $LOG_FILE
    echo "Error: Invalid input"
    exit 1
fi

if [ "$DEVICE" = "wifi0" ]; then
    DEVICE_INDEX=0
    IFACE_INDEX=0
elif [ "$DEVICE" = "wifi1" ]; then
    DEVICE_INDEX=1
    IFACE_INDEX=1
else
    echo "Invalid device: $DEVICE" >> $LOG_FILE
    echo "Error: Invalid device: $DEVICE"
    exit 1
fi

uci set wireless.@wifi-device[$DEVICE_INDEX].type="$TYPE"
uci set wireless.@wifi-device[$DEVICE_INDEX].channel="$CHANNEL"
uci set wireless.@wifi-device[$DEVICE_INDEX].macaddr="$MACADDR"
uci set wireless.@wifi-device[$DEVICE_INDEX].hwmode="$HWMODE"
uci set wireless.@wifi-device[$DEVICE_INDEX].disabled="$DISABLED"

uci set wireless.@wifi-iface[$IFACE_INDEX].device="$IFACE_DEVICE"
uci set wireless.@wifi-iface[$IFACE_INDEX].network="$IFACE_NETWORK"
uci set wireless.@wifi-iface[$IFACE_INDEX].mode="$IFACE_MODE"
uci set wireless.@wifi-iface[$IFACE_INDEX].ssid="$IFACE_SSID"
uci set wireless.@wifi-iface[$IFACE_INDEX].encryption="$IFACE_ENCRYPTION"

uci commit wireless
wifi

uci show wireless >> $LOG_FILE

echo "Wi-Fi Configuration for $DEVICE saved and applied."
echo "Configuration saved successfully" >> $LOG_FILE


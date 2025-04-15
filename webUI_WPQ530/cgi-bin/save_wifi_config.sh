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

get_current_band() {
    local device=$1
    local channel_freq=$(iw dev "$device" info | awk -F'[()]' '/channel/ {print $2+0; exit}')

    if [ -z "$channel_freq" ]; then
        echo "Unknown"
        return
    fi

    if [ "$channel_freq" -ge 2412 ] && [ "$channel_freq" -le 2484 ]; then
        echo "2"
    elif [ "$channel_freq" -ge 5180 ] && [ "$channel_freq" -le 5885 ]; then
        echo "5"
    elif [ "$channel_freq" -ge 5955 ] && [ "$channel_freq" -le 7115 ]; then
        echo "6"
    else
        echo "Unknown"
    fi
}

delete_other_ifaces() {
    local device="$1"
    local current_iface="$2"

    echo "Deleting all ifaces on $device except $current_iface" >> $LOG_FILE

    for iface in $(uci show wireless | grep "wireless.@wifi-iface" | grep "$device" | awk -F'.' '{print $2}'); do
        if [ "$iface" != "$current_iface" ]; then
            echo "Deleting iface: $iface" >> $LOG_FILE
            uci delete wireless.$iface
        fi
    done
    echo "Deleting done" >> $LOG_FILE
}

CURRENT_BAND=$(get_current_band $DEVICE)
echo "Current Band: $CURRENT_BAND" >> $LOG_FILE

SUPPORTED_BANDS_FILE="/sys/class/net/$DEVICE/supported_bands"
if [ -f "$SUPPORTED_BANDS_FILE" ]; then
    SUPPORTED_BANDS=$(cat "$SUPPORTED_BANDS_FILE")
    echo "Supported Bands: $SUPPORTED_BANDS" >> $LOG_FILE
else
    SUPPORTED_BANDS="Unknown"
fi

if echo "$SUPPORTED_BANDS" | grep -q "5GHz/6GHz"; then
    if [ "$CURRENT_BAND" = "5" ] && [ "$BAND" = "3" ]; then
        echo "Switching from 5GHz to 6GHz: Setting channel=1 and band=3" >> $LOG_FILE
        uci set wireless.$DEVICE.channel="1"
        uci set wireless.$DEVICE.band="3"
        uci set wireless.$DEVICE.htmode="EHT320"
        uci set wireless.$IFACE_NAME.en_6g_sec_comp='0'
        uci commit wireless
        uci show wireless >> $LOG_FILE
        wifi
        echo "Switching done" >> $LOG_FILE
        delete_other_ifaces "$DEVICE" "$IFACE_NAME"
        uci commit wireless
        uci show wireless >> $LOG_FILE
        wifi
    elif [ "$CURRENT_BAND" = "6" ] && [ "$BAND" = "2" ]; then
        echo "Switching from 6GHz to 5GHz: Setting channel=1 and band=0" >> $LOG_FILE
        uci set wireless.$DEVICE.channel="1"
        uci set wireless.$DEVICE.htmode="EHT160"
        uci delete wireless.$DEVICE.band="0"
        uci delete wireless.$IFACE_NAME.en_6g_sec_comp
        uci commit wireless
        uci show wireless >> $LOG_FILE
        wifi
        echo "Switching done" >> $LOG_FILE
        delete_other_ifaces "$DEVICE" "$IFACE_NAME"
        uci commit wireless
        uci show wireless >> $LOG_FILE
        wifi
    fi
fi

wifi

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

if [ "$BAND" = "3" ]; then
    echo "Detected 6GHz band, applying specific settings" >> $LOG_FILE
    uci set wireless.$DEVICE.band=3
    uci set wireless.$IFACE_NAME.en_6g_sec_comp='0'
fi

if [ "$BAND" = "1" ]; then
    echo "Detected 2.4GHz band, applying specific settings" >> $LOG_FILE
    uci set wireless.$IFACE_NAME.disablecoext='1'
    uci set wireless.$IFACE_NAME.vht_11ng='1'
fi

ENCRYPTION_TYPE=$(echo "$IFACE_ENCRYPTION" | cut -d'+' -f1) # 取 `sae+CCMP` 的 `sae`

if [ "$ENCRYPTION_TYPE" = "sae" ]; then
    echo "SAE detected, setting encryption to CCMP" >> $LOG_FILE
    uci set wireless.$IFACE_NAME.encryption='ccmp'
    uci set wireless.$IFACE_NAME.sae='1'

    if [ -n "$IFACE_KEY" ]; then
        uci -q delete wireless.$IFACE_NAME.key
        uci -q delete wireless.$IFACE_NAME.sae_password
        uci add_list wireless.$IFACE_NAME.sae_password="$IFACE_KEY"
        echo "SAE enabled with sae_password" >> $LOG_FILE
    fi
else
    uci -q delete wireless.$IFACE_NAME.sae
    uci -q delete wireless.$IFACE_NAME.sae_password

    if [ -n "$IFACE_KEY" ]; then
        uci set wireless.$IFACE_NAME.key="$IFACE_KEY"
        echo "Regular encryption, key applied" >> $LOG_FILE
    fi

    uci set wireless.$IFACE_NAME.encryption="$IFACE_ENCRYPTION"
fi

if [ "$IFACE_MODE" = "sta" ]; then
    echo "STA mode detected, enabling extap=1" >> $LOG_FILE
    uci set wireless.$IFACE_NAME.extap='1'
else
    echo "AP mode detected, removing extap" >> $LOG_FILE
    uci -q delete wireless.$IFACE_NAME.extap
fi

CURRENT_CHANNEL_MHZ=$(echo "$INPUT" | jsonfilter -e '@.current_channel')

echo "CHANNEL=$CHANNEL" >> $LOG_FILE
echo "CURRENT_CHANNEL_MHZ=$CURRENT_CHANNEL_MHZ" >> $LOG_FILE

if [ -z "$DEVICE" ]; then
    echo "Error: DEVICE is empty" >> $LOG_FILE
    exit 1
fi

uci set wireless.$IFACE_NAME.device="$DEVICE"
uci set wireless.$IFACE_NAME.network="lan"
uci set wireless.$IFACE_NAME.mode="$IFACE_MODE"
uci set wireless.$IFACE_NAME.ssid="$IFACE_SSID"

if [ "$IFACE_ENCRYPTION" = "none" ]; then
    uci -q delete wireless.$IFACE_NAME.key
    echo "Encryption is none, deleted key" >> $LOG_FILE
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
uci show wireless | grep "@wifi-iface" >> $LOG_FILE

uci commit wireless
sleep 2

echo "Checking UCI after commit:" >> $LOG_FILE
uci show wireless | grep "@wifi-iface" >> $LOG_FILE

QCACFG_EXISTS=$(uci show wireless | grep -q 'wireless.qcawifi=qcawifi' && echo "1" || echo "0")

QCACFG_EXISTS=$(uci show wireless | grep -q 'wireless.qcawifi=qcawifi' && echo "1" || echo "0")

if [ "$QCACFG_EXISTS" -eq "0" ]; then
    echo "Adding missing wireless.qcawifi configuration" >> $LOG_FILE
    uci set wireless.qcawifi=qcawifi
    uci set wireless.qcawifi.non_mlo_11be_ap_operation_enable='1'
    uci commit wireless
    echo "Configuration added. Rebooting system..." >> $LOG_FILE
    reboot
else
    echo "wireless.qcawifi already exists. Reloading Wi-Fi..." >> $LOG_FILE
    wifi reload
fi

echo "Configuration saved successfully"
echo "Wi-Fi Configuration for $DEVICE saved and applied." >> $LOG_FILE
uci show wireless >> $LOG_FILE


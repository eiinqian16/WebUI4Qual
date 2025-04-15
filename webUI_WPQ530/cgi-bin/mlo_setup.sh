#!/bin/sh
echo "Content-Type: text/plain"
echo ""

LOG_FILE="/tmp/mlo_setup.log"

echo "---- New MLO Setup ----" >> $LOG_FILE
date >> $LOG_FILE

INPUT=$(cat)
DISABLE_MLO=$(echo "$INPUT" | jsonfilter -e '@.disable_mlo')

bootargs=console=ttyMSM0,115200n8 cnss2.enable_mlo_support=1 cnss2.bdf_integrated=0x12 cnss2.bdf_pci1=0x1006


if [ "$DISABLE_MLO" = "true" ]; then
    echo "Disabling MLO..." >> $LOG_FILE
    
    uci -q delete wireless.mld0
    echo "Removed MLO configuration." >> $LOG_FILE
    
    for IFACE in $(uci show wireless | grep -E "wireless.@wifi-iface\[[0-9]+\].mld='mld0'" | awk -F'[][]' '{print $2}'); do
        echo "Removing MLD from iface index $IFACE" >> $LOG_FILE
        uci -q delete wireless.@wifi-iface[$IFACE].mld
    done

    uci set wireless.qcawifi=qcawifi
    uci set wireless.qcawifi.non_mlo_11be_ap_operation_enable=1
    echo "Enabled non-MLO 11be AP operation." >> $LOG_FILE

    uci commit wireless
    echo "0,-" > /www/compex-web-ui/cgi-bin/mlo-status

    echo "MLO Disabled and non-MLO mode enabled." >> $LOG_FILE
    reboot
    exit 0
fi


MLO_SSID=$(echo "$INPUT" | jsonfilter -e '@.ssid')
MLO_PASSWORD=$(echo "$INPUT" | jsonfilter -e '@.password')
MLO_COMBO=$(echo "$INPUT" | jsonfilter -e '@.combo')

echo "1,$MLO_COMBO" > /www/compex-web-ui/cgi-bin/mlo-status

if [ -z "$MLO_SSID" ] || [ -z "$MLO_PASSWORD" ] || [ -z "$MLO_COMBO" ]; then
    echo "Error: Missing parameters (SSID, Password, Combo)" >> $LOG_FILE
    exit 1
fi

echo "SSID: $MLO_SSID, Password: ********, Combo: $MLO_COMBO" >> $LOG_FILE
echo "Copying default wireless config..." >> $LOG_FILE
cp /www/compex-web-ui/mlo_wireless_config /etc/config/wireless

get_band() {
    local device=$1
    local band_file="/sys/class/net/$device/supported_bands"
    if [ -f "$band_file" ]; then
        cat "$band_file" | tr -d '\n' | sed 's/\/$//'
    else
        echo "Unknown"
    fi
}

WIFI_2G=""
WIFI_5G=""
WIFI_6G=""

for dev in wifi0 wifi1 wifi2 wifi3; do
    BAND=$(get_band $dev)
    echo "Checking $dev -> Band: '$BAND'" >> $LOG_FILE
    case "$BAND" in
        "2GHz") WIFI_2G=$dev ;;
        "5GHz") WIFI_5G=$dev ;;
        "6GHz") WIFI_6G=$dev ;;
    esac
done

echo "Detected: 2G=$WIFI_2G, 5G=$WIFI_5G, 6G=$WIFI_6G" >> $LOG_FILE

case "$MLO_COMBO" in
    "2G5G") WIFI_LIST="$WIFI_2G $WIFI_5G" ;;
    "5G6G") WIFI_LIST="$WIFI_5G $WIFI_6G" ;;
    "2G6G") WIFI_LIST="$WIFI_2G $WIFI_6G" ;;
    "2G5G6G") WIFI_LIST="$WIFI_2G $WIFI_5G $WIFI_6G" ;;
    *)
        echo "Invalid MLO combination: $MLO_COMBO" >> $LOG_FILE
        exit 1
        ;;
esac

echo "Applying MLO settings..." >> $LOG_FILE
uci set wireless.mld0=wifi-mld
uci set wireless.mld0.mld_ssid="$MLO_SSID"

USED_IFACES=""

for WIFI_DEV in $WIFI_LIST; do
    BAND=$(get_band $WIFI_DEV)
    IFACE_INDEX=$(uci show wireless | grep -E "wireless.@wifi-iface\[[0-9]+\].device='$WIFI_DEV'" | awk -F'[][]' '{print $2}' | head -n 1)

    if [ -z "$IFACE_INDEX" ]; then
        echo "ERROR: No iface found for $WIFI_DEV!" >> $LOG_FILE
        exit 1
    fi

    echo "Assigning $WIFI_DEV to iface index $IFACE_INDEX" >> $LOG_FILE
    USED_IFACES="$USED_IFACES $IFACE_INDEX"

    uci set wireless.@wifi-iface[$IFACE_INDEX].ssid="$MLO_SSID"
    uci set wireless.@wifi-iface[$IFACE_INDEX].mld='mld0'
    uci set wireless.@wifi-iface[$IFACE_INDEX].mode='ap'
    uci set wireless.@wifi-iface[$IFACE_INDEX].encryption='ccmp'
    uci set wireless.@wifi-iface[$IFACE_INDEX].sae='1'
    uci set wireless.@wifi-iface[$IFACE_INDEX].ieee80211w='2'
    uci add_list wireless.@wifi-iface[$IFACE_INDEX].sae_password="$MLO_PASSWORD"
    uci set wireless.$WIFI_DEV.disabled='0' 

    case "$BAND" in
        "2GHz")
            echo "Applying 2GHz specific settings to iface index $IFACE_INDEX" >> $LOG_FILE
            uci set wireless.@wifi-iface[$IFACE_INDEX].disablecoext=1
            uci set wireless.@wifi-iface[$IFACE_INDEX].vht_11ng=1
	    uci set wireless.$WIFI_DEV.htmode='EHT40'
            ;;
        "6GHz")
            echo "Applying 6GHz specific settings to iface index $IFACE_INDEX" >> $LOG_FILE
            uci set wireless.$WIFI_DEV.band='3'
            uci set wireless.@wifi-iface[$IFACE_INDEX].en_6g_sec_comp='0'
            ;;
    esac
done

USED_IFACES=$(echo "$USED_IFACES" | sed 's/^ //')
echo "Final USED_IFACES: $USED_IFACES" >> $LOG_FILE

for IFACE in $(uci show wireless | grep -E "wireless.@wifi-iface\[[0-9]+\]" | awk -F'[][]' '{print $2}'); do
    if ! echo "$USED_IFACES" | tr ' ' '\n' | grep -Fxq "$IFACE"; then
        echo "Setting unused iface index $IFACE SSID to '-'" >> $LOG_FILE
        uci set wireless.@wifi-iface[$IFACE].ssid="-"
    fi
done

uci commit wireless
wifi
echo "Final Wireless Config:" >> $LOG_FILE
uci show wireless >> $LOG_FILE
echo "MLO setup completed successfully!" >> $LOG_FILE


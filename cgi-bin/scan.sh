#!/bin/sh
echo "Content-Type: application/json"
echo ""

QUERY_STRING=$(echo "$QUERY_STRING" | sed 's/%3D/=/g')
DEVICE=$(echo "$QUERY_STRING" | grep -o 'device=[^&]*' | cut -d '=' -f 2)

if [ -z "$DEVICE" ]; then
    echo "{\"error\": \"No device specified. Use device=wifi0, device=wifi1, or device=wifi2.\"}"
    exit 1
fi

WIFI_DEVICE=$DEVICE
SCAN_FILE="/tmp/scan_iface"

convert_dbm_to_percentage() {
    local dbm=$1
    echo "$dbm" | awk '{print int((100 + $1) * 100 / 100)}'
}

convert_dbm_to_quality() {
    local dbm=$1
    echo "$dbm" | awk '{if ($1 >= -30) print "Excellent"; else if ($1 >= -60) print "Good"; else if ($1 >= -80) print "Weak"; else print "Very Weak"}'
}

check_and_enable_device() {
    local device=$1
    local is_disabled=$(uci get wireless.$device.disabled 2>/dev/null)

    if [ "$is_disabled" = "1" ]; then
        echo "Device $device is disabled. Enabling it..." >&2
        uci set wireless.$device.disabled=0
        uci commit wireless
        wifi 
        sleep 5  
    fi
}

create_temp_vap() {
    local device=$1
    local vap=""
    local vap_prefix=""
    echo "" > $SCAN_FILE
    
    case "$device" in
        "wifi0")
            vap_prefix="ath0" 
            ;;
        "wifi1")
            vap_prefix="ath1" 
            ;;
        "wifi2")
            vap_prefix="ath2"
            ;;
        *)
            echo "{\"error\": \"Unsupported device: $device\"}"
            exit 1
            ;;
    esac

    echo "Checking existing VAPs for $device..." >&2
    vap=$(iw dev | grep -o "$vap_prefix" | tail -n 1)

    if [ -n "$vap" ]; then
        echo "Found existing VAP: $vap" >&2
        echo "$vap" > $SCAN_FILE  
        return 0  
    fi

    echo "Creating temporary VAP for $device..." >&2
    uci add wireless wifi-iface
    uci set wireless.@wifi-iface[-1].device=$device
    uci set wireless.@wifi-iface[-1].mode='ap'
    uci set wireless.@wifi-iface[-1].ssid='temp-scan'
    uci set wireless.@wifi-iface[-1].encryption='none'
    uci set wireless.@wifi-iface[-1].hidden='1'
    uci commit wireless
    wifi  
    sleep 6

    echo "Rechecking VAPs for $device..." >&2
    vap=$(iw dev | grep -o "$vap_prefix" | tail -n 1)
    echo "what is the vap : $vap" 
    if [ -n "$vap" ]; then
        echo "$vap" > $SCAN_FILE 
        return 0
    else
        echo "{\"error\": \"Failed to create VAP for $device\"}"
        exit 1 
    fi
}

read_vap_from_file() {
    if [ ! -f "$SCAN_FILE" ]; then
        echo "{\"error\": \"Scan interface file not found.\"}"
        exit 1
    fi
    
    local vap=$(cat $SCAN_FILE)
    
    if [ -z "$vap" ]; then
        echo "{\"error\": \"No VAP interface found. Please check the configuration.\"}"
        exit 1
    fi
    
    echo "Ready to scan with VAP: $vap" >&2
    scan_vap "$vap"
}

scan_vap() {
    local vap=$1
    echo "{"
    echo "\"device\": \"$WIFI_DEVICE\","
    echo "\"interface\": \"$vap\","
    echo "\"scan_time\": \"$(date "+%Y-%m-%d %H:%M:%S")\","
    echo "\"results\": ["

    iw dev $vap scan | awk '
    /freq:/ {freq=$2}
    /signal:/ {signal=$2}
    /SSID:/ {ssid=$2; if(ssid!="") {print signal, freq, ssid}}
    ' | sort -n | while read -r signal freq ssid
    do
        percent=$(convert_dbm_to_percentage $signal)
        quality=$(convert_dbm_to_quality $signal)
        echo "{"
        echo "\"signal\": \"$signal\","
        echo "\"strength\": \"$percent\","
        echo "\"quality\": \"$quality\","
        echo "\"frequency\": \"$freq\","
        echo "\"ssid\": \"$ssid\""
        echo "},"
    done
    
    echo "{}" 
    echo "]"
    echo "}"
}

check_and_enable_device $WIFI_DEVICE
create_temp_vap $WIFI_DEVICE
read_vap_from_file


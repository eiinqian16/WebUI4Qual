#!/bin/sh
echo "Content-Type: application/json"
echo ""

get_channel_number() {
    local freq=$1
    if [ "$freq" -ge 2412 ] && [ "$freq" -le 2484 ]; then
        echo $(( (freq - 2407) / 5 ))
        return
    fi
    if [ "$freq" -ge 5180 ] && [ "$freq" -le 5885 ]; then
        echo $(( (freq - 5000) / 5 ))
        return
    fi
    if [ "$freq" -ge 5955 ] && [ "$freq" -le 7115 ]; then
        echo $(( (freq - 5950) / 5 ))
        return
    fi
    echo "?"
}

get_current_channel(){
    local device=$1
    iw dev | awk -v dev="$device" '$0 ~ "Interface " dev "$" {found=1} found && /channel/ {print $2; exit}'
}

get_current_freq() {
    local device=$1
    iw dev | awk -v dev="$device" '$0 ~ "Interface " dev "$" {found=1} found && /channel/ {print $2, $3; exit}' | awk -F '[()]' '{print $2}'
}


get_current_band() {
    local freq_mhz=$1
    if [ "$freq_mhz" -ge 2412 ] && [ "$freq_mhz" -le 2484 ]; then
        echo "2.4GHz"
    elif [ "$freq_mhz" -ge 5180 ] && [ "$freq_mhz" -le 5885 ]; then
        echo "5GHz"
    elif [ "$freq_mhz" -ge 5955 ] && [ "$freq_mhz" -le 7115 ]; then
        echo "6GHz"
    else
        echo "Unknown"
    fi
}

get_bitrate_from_iwconfig() {
    local device=$1
    local iface=""

    [ "$device" = "wifi0" ] && iface="ath0"
    [ "$device" = "wifi1" ] && iface="ath1"
    [ "$device" = "wifi2" ] && iface="ath2"

    echo "DEBUG: device=$device, iface=$iface" >&2

    if [ -z "$iface" ]; then
        echo "Unknown"
        return
    fi

    iwconfig "$iface" 2>/dev/null | grep "Bit Rate" >&2
    iwconfig "$iface" 2>/dev/null | grep "Bit Rate" | awk -F'[: ]+' '{print $4,$5}'
}

get_iface_ssid_map() {
    iw dev | awk '
    /Interface/ { iface=$2 }
    /ssid/ { ssid=$2; print iface, ssid }
    ' > /tmp/iface_ssid_map.txt
}

get_bssid_by_ssid() {
    local target_ssid="$1"
    local mode="$2"
    local iface
    local bssid="Unknown"

    while read iface ssid; do
        if [ "$ssid" = "$target_ssid" ]; then
            if [ "$mode" = "ap" ]; then
                bssid=$(cat /sys/class/net/$iface/address 2>/dev/null)
            elif [ "$mode" = "sta" ]; then
                bssid=$(iw dev "$iface" link | awk '/Connected to/ {print $3}')
            fi
            break
        fi
    done < /tmp/iface_ssid_map.txt

    echo "$bssid"
}

if [ -f "$MLO_STATUS_FILE" ]; then
    MLO_INFO=$(cat "$MLO_STATUS_FILE")
else
    MLO_INFO="0,-"
fi

MLO_STATUS_FILE="/www/compex-web-ui/cgi-bin/mlo-status"

if [ -f "$MLO_STATUS_FILE" ]; then
    MLO_INFO=$(cat "$MLO_STATUS_FILE" | tr -d '\r') 
else
    MLO_INFO="0,-"
fi

MLO_STATUS=$(echo "$MLO_INFO" | cut -d',' -f1)
MLO_BANDS=$(echo "$MLO_INFO" | cut -d',' -f2)

echo "{"
echo "  \"mlo_status\": \"$MLO_STATUS\","
echo "  \"mlo_bands\": \"$MLO_BANDS\","


wifi_devices=$(uci show wireless | grep "=wifi-device" | cut -d. -f2 | cut -d= -f1)
total_devices=$(echo "$wifi_devices" | wc -l)
count=0

for device in $wifi_devices; do
    type=$(uci get wireless.$device.type 2>/dev/null)
    channel=$(uci get wireless.$device.channel 2>/dev/null)
    current_channel=$(get_current_channel $device)
    current_freq=$(get_current_freq "$device")
    current_band=$(get_current_band "$current_freq")
    bitrate=$(get_bitrate_from_iwconfig $device)
    hwmode=$(uci get wireless.$device.hwmode 2>/dev/null)
    htmode=$(uci get wireless.$device.htmode 2>/dev/null)
    disabled=$(uci get wireless.$device.disabled 2>/dev/null)
    txpower=$(uci get wireless.$device.txpower 2>/dev/null)
    country=$(uci get wireless.$device.country 2>/dev/null)

    echo "  \"$device\": {"
    echo "    \"device\": \"$device\","
    echo "    \"type\": \"$type\","
    echo "    \"channel\": \"$channel\","
    echo "    \"current_channel\": \"$current_channel\","
    echo "    \"current_band\": \"$current_band\","
    echo "    \"bitrate\": \"$bitrate\","
    echo "    \"hwmode\": \"$hwmode\","

    if [ -n "$htmode" ]; then
        echo "    \"htmode\": \"$htmode\","
    fi

    echo "    \"disabled\": \"$disabled\","
    echo "    \"txpower\": \"$txpower\","
    echo "    \"country\": \"$country\","

    freq_list_file="/sys/class/net/$device/supported_freq_list"
    if [ -f "$freq_list_file" ]; then
        freq_list=$(cat "$freq_list_file")

        echo "    \"channel_options\": {"
        first_band=1

        channels_24=""
        for freq in $freq_list; do
            if [ "$freq" -ge 2412 ] && [ "$freq" -le 2484 ]; then
                channel_num=$(get_channel_number $freq)
                channels_24="$channels_24 \"$channel_num ($freq MHz)\","
            fi
        done
        if [ -n "$channels_24" ]; then
            if [ "$first_band" -eq 0 ]; then echo ","; fi
            first_band=0
            echo "      \"2.4GHz\": [\"auto (2.4GHz)\",${channels_24%?}]"
        fi

        channels_5=""
        for freq in $freq_list; do
            if [ "$freq" -ge 5180 ] && [ "$freq" -le 5885 ]; then
                channel_num=$(get_channel_number $freq)
                channels_5="$channels_5 \"$channel_num ($freq MHz)\","
            fi
        done
        if [ -n "$channels_5" ]; then
            if [ "$first_band" -eq 0 ]; then echo ","; fi
            first_band=0
            echo "      \"5GHz\": [\"auto (5GHz)\",${channels_5%?}]"
        fi

        channels_6=""
        for freq in $freq_list; do
            if [ "$freq" -ge 5955 ] && [ "$freq" -le 7115 ]; then
                channel_num=$(get_channel_number $freq)
                channels_6="$channels_6 \"$channel_num ($freq MHz)\","
            fi
        done
        if [ -n "$channels_6" ]; then
            if [ "$first_band" -eq 0 ]; then echo ","; fi
            echo "      \"6GHz\": [\"auto (6GHz)\",${channels_6%?}]"
        fi

        echo "    },"
    fi

    supported_bands_file="/sys/class/net/$device/supported_bands"
    if [ -f "$supported_bands_file" ]; then
        supported_bands=$(tr '\n' '/' < "$supported_bands_file" | sed 's:/$::')
    else
        supported_bands="unknown"
    fi

    echo "    \"supported_bands\": \"$supported_bands\","

    echo "    \"interfaces\": ["

    wifi_ifaces=$(uci show wireless | grep "=wifi-iface" | cut -d. -f2 | cut -d=                                                                                                                             -f1)
    first_iface=1

    get_iface_ssid_map

    for iface in $wifi_ifaces; do
        iface_device=$(uci get wireless.$iface.device 2>/dev/null)
        if [ "$iface_device" = "$device" ]; then
            network=$(uci get wireless.$iface.network 2>/dev/null)
            mode=$(uci get wireless.$iface.mode 2>/dev/null)
            ssid=$(uci get wireless.$iface.ssid 2>/dev/null)
            full_encryption=$(uci get wireless.$iface.encryption 2>/dev/null)
            sae_enabled=$(uci get wireless.$iface.sae 2>/dev/null)

            encryption=""
            cipher="auto"

            if [ "$sae_enabled" = "1" ]; then
                encryption="sae"
                cipher="CCMP"
                key=$(uci get wireless.$iface.sae_password 2>/dev/null)
            else
                if echo "$full_encryption" | grep -q '+'; then
                    encryption="${full_encryption%%+*}"
                    cipher="${full_encryption##*+}"
                else
                    encryption="$full_encryption"
                    case "$full_encryption" in
                        *tkip*) cipher="TKIP" ;;
                        *ccmp*) cipher="CCMP" ;;
                        *gcmp*) cipher="GCMP" ;;
                        *) cipher="auto" ;;
                    esac
                fi
                key=$(uci get wireless.$iface.key 2>/dev/null)
            fi
            bssid=$(get_bssid_by_ssid "$ssid" "$mode")

            if [ "$first_iface" -eq 0 ]; then
                echo ","
            fi

            first_iface=0

            echo "      {"
            echo "        \"iface\": \"$iface\","
            echo "        \"network\": \"$network\","
            echo "        \"mode\": \"$mode\","
            echo "        \"ssid\": \"$ssid\","
            echo "        \"bssid\": \"$bssid\","
            echo "        \"encryption\": \"$encryption\","
            echo "        \"cipher\": \"$cipher\""

            if [ -n "$key" ]; then
                echo "        ,\"key\": \"$key\""
            fi

            echo "      }"
        fi
    done

    echo ""
    echo "    ]"
    count=$((count + 1))
    if [ $count -lt $total_devices ]; then
        echo "  },"
    else
        echo "  }"
    fi
done

echo "}"


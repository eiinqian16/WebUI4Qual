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

get_iface_for_radio() {
    local radio=$1
    local phy_index=${radio#radio}
    iw dev | awk -v p="$phy_index" '
        /phy#/ {phy=$1; sub("phy#","",phy)}
        /Interface/ {iface=$2; if(phy==p) {print iface; exit}}
    '
}

get_current_channel(){
    local device=$1
    dev=$(get_iface_for_radio $device)
    iw dev "$dev" info 2>/dev/null | awk '/channel/ {print $2; exit}'
}

get_current_freq() {
    local device=$1
    dev=$(get_iface_for_radio $device)
    iw dev "$dev" info 2>/dev/null | awk '/channel/ {print $3; exit}' | awk -F '(' '{print $2; exit}'
}

get_current_band() {
    local freq_mhz=$(get_current_freq $1)
    if [ -z "$freq_mhz" ]; then
        local uci_band=$(uci -q get wireless.$1.band)
        case "$uci_band" in
            2g) echo "2.4GHz" ;;
            5g) echo "5GHz" ;;
            6g) echo "6GHz" ;;
            *) echo "Unknown" ;;
        esac
        return
    fi
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

get_bitrate_from_iwinfo() {
    local device=$1
    local iface=$(get_iface_for_radio $device)
    if [ -z "$iface" ]; then
        echo "Unknown"
        return
    fi
    iwinfo "$iface" info 2>/dev/null | grep "Bit Rate" | awk -F ':' '{print $2, $3}'
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
                bssid=$(iw dev "$iface" link 2>/dev/null | awk '/Connected to/ {print $3}')
            fi
            [ -n "$bssid" ] && break || bssid="Unknown"
        fi
    done < /tmp/iface_ssid_map.txt
    echo "$bssid"
}

get_cur_txpower() {
    local device=$1
    dev=$(get_iface_for_radio $device)
    iwinfo "$dev" info 2>/dev/null | grep -i "tx-power" | awk -F ':' '{print $2; exit}' | awk '{print $1}'
}

get_cur_enabled() {
    uci -q get wireless.$1.disabled || echo "0"
}

get_hwmode() {
    local htmode=$1
    case "$htmode" in 
        *EHT*) echo "11be" ;;
        *HE*)  echo "11ax" ;;
        *HT*)  echo "11n" ;;
        *VHT*) echo "11ac" ;;
        *)     echo "legacy" ;;
    esac
}

echo "{"
wifi_devices=$(uci show wireless | grep "=wifi-device" | cut -d. -f2 | cut -d= -f1)
total_devices=$(echo "$wifi_devices" | wc -l)
count=0
for device in $wifi_devices; do
    count=$((count + 1))
    echo "  \"$device\": {"
    echo "    \"device\": \"$device\","
    echo "    \"type\": \"$(uci -q get wireless.$device.type)\","
    echo "    \"channel\": \"$(uci -q get wireless.$device.channel)\","
    echo "    \"current_channel\": \"$(get_current_channel $device)\","
    echo "    \"current_band\": \"$(get_current_band $device)\","
    echo "    \"bitrate\": \"$(get_bitrate_from_iwinfo $device)\","
    htmode=$(uci -q get wireless.$device.htmode)
    echo "    \"hwmode\": \"$(get_hwmode $htmode)\","
    [ -n "$htmode" ] && echo "    \"htmode\": \"$htmode\","
    echo "    \"disabled\": \"$(get_cur_enabled $device)\","
    echo "    \"txpower\": \"$(get_cur_txpower $device)\","
    echo "    \"country\": \"$(uci -q get wireless.$device.country)\","
    
    freq_list_file="/tmp/sysnet/$(get_iface_for_radio $device)/supported_freq_list"
    if [ -f "$freq_list_file" ]; then
        freq_list=$(cat "$freq_list_file")
        echo "    \"channel_options\": {"
        first_band=1
        for band_name in "2.4GHz" "5GHz" "6GHz"; do
            case "$band_name" in
                "2.4GHz") min=2412; max=2484 ;;
                "5GHz")   min=5180; max=5885 ;;
                "6GHz")   min=5955; max=7115 ;;
            esac
            channels=""
            for freq in $freq_list; do
                if [ "$freq" -ge $min ] && [ "$freq" -le $max ]; then
                    channels="$channels \"$(get_channel_number $freq) ($freq MHz)\","
                fi
            done
            if [ -n "$channels" ]; then
                [ "$first_band" -eq 0 ] && echo ","
                echo -n "      \"$band_name\": [\"auto ($band_name)\",${channels%?}]"
                first_band=0
            fi
        done
        echo -e "\n    },"
    fi
    echo "    \"supported_bands\": \"$(get_current_band $device)\","
    echo "    \"interfaces\": ["
    first_iface=1
    get_iface_ssid_map
    for iface in $(uci show wireless | grep "=wifi-iface" | cut -d. -f2 | cut -d= -f1); do
        if [ "$(uci -q get wireless.$iface.device)" = "$device" ]; then
            [ $first_iface -eq 0 ] && echo ","
            ssid=$(uci -q get wireless.$iface.ssid)
            mode=$(uci -q get wireless.$iface.mode)
            full_enc=$(uci -q get wireless.$iface.encryption)
            sae=$(uci -q get wireless.$iface.sae)
            [ "$sae" = "1" ] && { encryption="sae"; cipher="CCMP"; key=$(uci -q get wireless.$iface.sae_password); } || {
                if echo "$full_enc" | grep -q '+'; then encryption="${full_enc%%+*}"; cipher="${full_enc##*+}"
                else encryption="$full_enc"; case "$full_enc" in *tkip*) cipher="TKIP";; *ccmp*) cipher="CCMP";; *gcmp*) cipher="GCMP";; *) cipher="auto";; esac; fi
                key=$(uci -q get wireless.$iface.key)
            }
            echo "      {\"iface\": \"$iface\", \"network\": \"$(uci -q get wireless.$iface.network)\", \"mode\": \"$mode\", \"ssid\": \"$ssid\", \"bssid\": \"$(get_bssid_by_ssid "$ssid" "$mode")\", \"encryption\": \"$encryption\", \"cipher\": \"$cipher\" $([ -n "$key" ] && echo ",\"key\": \"$key\"")}"
            first_iface=0
        fi
    done
    echo "    ]"
    [ $count -lt $total_devices ] && echo "  }," || echo "  }"
done
echo "}"

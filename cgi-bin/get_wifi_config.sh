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

echo "{"
wifi_devices=$(uci show wireless | grep "=wifi-device" | cut -d. -f2 | cut -d= -f1)
total_devices=$(echo "$wifi_devices" | wc -l)
count=0

for device in $wifi_devices; do
    type=$(uci get wireless.$device.type 2>/dev/null)
    channel=$(uci get wireless.$device.channel 2>/dev/null)
    hwmode=$(uci get wireless.$device.hwmode 2>/dev/null)
    htmode=$(uci get wireless.$device.htmode 2>/dev/null) 
    disabled=$(uci get wireless.$device.disabled 2>/dev/null)
    txpower=$(uci get wireless.$device.txpower 2>/dev/null)
    country=$(uci get wireless.$device.country 2>/dev/null)

    echo "  \"$device\": {"
    echo "    \"device\": \"$device\","
    echo "    \"type\": \"$type\","
    echo "    \"channel\": \"$channel\","
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
            echo "      \"2.4GHz\": [\"auto\",${channels_24%?}]"
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
            echo "      \"5GHz\": [\"auto\",${channels_5%?}]"
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
            echo "      \"6GHz\": [\"auto\",${channels_6%?}]"
        fi

        echo "    },"
    fi

    echo "    \"interfaces\": ["

    wifi_ifaces=$(uci show wireless | grep "=wifi-iface" | cut -d. -f2 | cut -d= -f1)
    first_iface=1

    for iface in $wifi_ifaces; do
        iface_device=$(uci get wireless.$iface.device 2>/dev/null)

        if [ "$iface_device" = "$device" ]; then
            network=$(uci get wireless.$iface.network 2>/dev/null)
            mode=$(uci get wireless.$iface.mode 2>/dev/null)
            ssid=$(uci get wireless.$iface.ssid 2>/dev/null)
            full_encryption=$(uci get wireless.$iface.encryption 2>/dev/null)
            key=$(uci get wireless.$iface.key 2>/dev/null)

            # 默认值
            encryption=""
            cipher="auto"

            # 拆分 encryption
            if echo "$full_encryption" | grep -q '+'; then
                encryption="${full_encryption%%+*}"  # 取 + 号前的 WPA 版本
                cipher="${full_encryption##*+}"  # 取 + 号后的 Cipher
            else
                encryption="$full_encryption"
                case "$full_encryption" in
                    *tkip*) cipher="TKIP" ;;
                    *ccmp*) cipher="CCMP" ;;
                    *gcmp*) cipher="GCMP" ;;
                    *) cipher="auto" ;;
                esac
            fi

            if [ "$first_iface" -eq 0 ]; then
                echo ","
            fi
            first_iface=0

            echo "      {"
            echo "        \"iface\": \"$iface\","
            echo "        \"network\": \"$network\","
            echo "        \"mode\": \"$mode\","
            echo "        \"ssid\": \"$ssid\","
            echo "        \"encryption\": \"$encryption\","
            echo "        \"cipher\": \"$cipher\""

            if [ "$encryption" != "none" ]; then
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


#!/bin/sh
echo "Content-type: application/json"
echo ""

# 获取所有 Wi-Fi 接口名（只取 athX 这种接口）
IFACES=$(iw dev | awk '/Interface/ {print $2}' | grep "^ath")

# 检查是否有接口
if [ -z "$IFACES" ]; then
    echo "[]"
    exit 0
fi

echo "["

first_iface=1
for IFACE in $IFACES; do
    # 获取接口模式（AP / STA）
    MODE=$(iw dev "$IFACE" info | grep type | awk '{print $2}')
    SSID=$(iw dev "$IFACE" info | grep ssid | awk '{print $2}')
    SSID=${SSID:-"Unknown"}

    if [ "$MODE" = "AP" ]; then
        # 获取 Associated Stations
        STATIONS=$(wlanconfig "$IFACE" list sta 2>/dev/null)

        if [ -n "$STATIONS" ]; then
            if [ "$first_iface" -eq 0 ]; then echo ","; fi
            first_iface=0

            echo "{"
            echo "  \"interface\": \"$IFACE\","
            echo "  \"mode\": \"AP\","
            echo "  \"ssid\": \"$SSID\","
            echo "  \"stations\": ["

            echo "$STATIONS" | awk '
                BEGIN { first_sta=1 }
                /^[0-9a-fA-F:]{17}/ {
                    if (first_sta) {
                        first_sta=0;
                    } else {
                        printf ",";
                    }
                    printf "\n    { \"mac\": \"%s\",", $1
                    sub("M", "", $4); sub("M", "", $5);
                    printf " \"tx_rate\": %s,", $4
                    printf " \"rx_rate\": %s,", $5
                    printf " \"rssi\": \"%s\" }", $6
                }
            '

            echo ""
            echo "  ]"
            echo "}"
        fi

    elif [ "$MODE" = "managed" ]; then
        # 获取 STA 连接的 AP 信息
        STA_INFO=$(iw dev "$IFACE" link)

        if ! echo "$STA_INFO" | grep -q "Not connected"; then
            MAC=$(echo "$STA_INFO" | grep "Connected to" | awk '{print $3}')
            SIGNAL=$(echo "$STA_INFO" | grep "signal" | awk '{print $2}')
            RX_RATE=$(echo "$STA_INFO" | grep "rx bitrate" | awk '{print $3}')
            TX_RATE=$(echo "$STA_INFO" | grep "tx bitrate" | awk '{print $3}')

            if [ "$first_iface" -eq 0 ]; then echo ","; fi
            first_iface=0

            echo "{"
            echo "  \"interface\": \"$IFACE\","
            echo "  \"mode\": \"STA\","
            echo "  \"ssid\": \"$SSID\","
            echo "  \"stations\": ["
            echo "    {"
            echo "      \"mac\": \"$MAC\","
            echo "      \"tx_rate\": $TX_RATE,"
            echo "      \"rx_rate\": $RX_RATE,"
            echo "      \"rssi\": \"$SIGNAL\""
            echo "    }"
            echo "  ]"
            echo "}"
        fi
    fi
done

echo "]"


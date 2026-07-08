#!/bin/sh
echo "Content-type: application/json"
echo ""

# 获取所有 Wi-Fi 接口名（只取 athX 这种接口）
IFACES=$(iw dev | awk '/Interface/ {print $2}' | grep "^wlan")

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
        STATIONS=$(iw "$IFACE" station dump 2>/dev/null)

        if [ -n "$STATIONS" ]; then
            if [ "$first_iface" -eq 0 ]; then echo ","; fi
            first_iface=0

            echo "{"
            echo "  \"interface\": \"$IFACE\","
            echo "  \"mode\": \"AP\","
            echo "  \"ssid\": \"$SSID\","
            echo "  \"stations\": ["

            echo "$STATIONS" | awk '
                BEGIN {
                print "["
                first_sta = 1
            }

            /^Station/ {
                if (!first_sta) {
                    printf ",\n"
                }
                first_sta = 0

                mac = $2
                tx_rate = ""
                rx_rate = ""
                rssi = ""
                connect_time = ""
            }

            /signal:/     { rssi = $2 }
            /tx bitrate:/ { tx_rate = $3 }
            /rx bitrate:/ { rx_rate = $3 }
            /connected time:/ { connect_time = $3 }

            /^$/ {
                if (mac != "") {
                    print "  {"
                    printf "    \"mac\": \"%s\",\n", mac
                    printf "    \"tx_rate\": \"%s\",\n", tx_rate
                    printf "    \"rx_rate\": \"%s\",\n", rx_rate
                    printf "    \"rssi\": \"%s\"\n", rssi
                    print "  }"
                    mac = ""
                }
            }

            END {
                if (mac != "") {
                    printf "  { \"mac\": \"%s\", \"tx_rate\": \"%s\", \"rx_rate\": \"%s\", \"rssi\": \"%s\" }", mac, tx_rate, rx_rate, rssi
                }
                print "\n]"
            }'

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


#!/bin/sh
LEASES="/tmp/dhcp.leases"

echo "Content-type: application/json"
echo ""

SSID0=$(uci get wireless.default_radio0.ssid)
SSID1=$(uci get wireless.default_radio1.ssid)

echo "["
first=1

for radio in wlan0 wlan1; do
    if [ "$radio" = "wlan0" ]; then current_ssid="$SSID0"; else current_ssid="$SSID1"; fi

    mac_list=$(clsapi get macfilter_maclist "$radio" | awk '{print $2}')

    for mac in $mac_list; do
        [ -z "$mac" ] && continue

        if [ "$first" -eq 0 ]; then echo ","; fi
        first=0

        lease_line=$(grep -i "$mac" "$LEASES" | head -1)

        if [ -n "$lease_line" ]; then
            ip=$(echo "$lease_line" | awk '{print $3}')
            name=$(echo "$lease_line" | awk '{print $4}')
            [ "$name" == "*" ] && name="Unknown"
        else
            ip="N/A"
            suffix=$(echo "$mac" | sed 's/://g' | tail -c 4 | tr 'a-z' 'A-Z')
            name="Device-$suffix"
        fi

        echo "  {"
        echo "      \"mac\":\"$mac\","
        echo "      \"ip\":\"$ip\","
        echo "      \"hostname\":\"$name\","
        echo "      \"ssid\":\"$current_ssid\""
        echo "  }"
    done
done

echo "]"

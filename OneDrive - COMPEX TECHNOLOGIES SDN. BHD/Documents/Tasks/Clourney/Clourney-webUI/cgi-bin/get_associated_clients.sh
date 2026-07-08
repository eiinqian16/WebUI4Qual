#!/bin/bash
echo "Content-type: application/json"
echo ""

get_clients() {
    local interface="$1"
    local mode="STA"
    local ssid=""

    if [ "$interface" == "wlan0" ]; then
        mode="2g"
        ssid=$(uci -q get wireless.default_radio0.ssid)
    elif [ "$interface" == "wlan1" ]; then
        mode="5g"
        ssid=$(uci -q get wireless.default_radio1.ssid)
    fi

    iw "$interface" station dump | awk -v mode="$mode" -v ssid="$ssid" '
    BEGIN { first = 1 }
    /^Station/ {
        if (!first) print "  },"
        first = 0
        mac = $2

        cmd = "grep -i \"" mac "\" /tmp/dhcp.leases 2>/dev/null"
        if ((cmd | getline line) > 0) {
            split(line, a, " ")
            ip = a[3]
            host = a[4]
        } else {
            ip = "N/A"
            host = "*"
        }
        close(cmd)

        if (host == "*" || host == "") {
            clean_mac = mac
            gsub(/:/, "", clean_mac)
            host = "Device-" toupper(substr(clean_mac, length(clean_mac)-3))
        }

        print "  {"
        print "    \"mac\": \"" mac "\","
        print "    \"ip\": \"" ip "\","
        print "    \"hostname\": \"" host "\","
        print "    \"mode\": \"" mode "\","
        print "    \"ssid\": \"" ssid "\","
    }
    /signal:/ { print "    \"signal\": " $2 "," }
    /tx bitrate:/ { print "    \"tx_bitrate\": " $3 "," }
    /rx bitrate:/ { print "    \"rx_bitrate\": " $3 }
    END {
        if (!first) print "  }"
    }'
}

echo "["

first_client=1
for iface in /sys/class/net/wlan*; do
    [ -e "$iface" ] || continue
    clients=$(get_clients "$(basename "$iface")")

    # Skip interfaces with no clients
    if [ -z "$clients" ]; then
        continue
    fi

    # Add comma only between JSON objects
    if [ $first_client -eq 0 ]; then
        echo ","
    fi
    first_client=0

    echo "$clients"
done

echo "]"

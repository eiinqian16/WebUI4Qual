#!/bin/sh
echo "Content-Type: application/json"
echo ""

wifi_list=$(ls /sys/class/net/ | grep -E '^wifi[0-9]+$')

first=1
echo "{"
for wifi in $wifi_list; do
    [ $first -eq 0 ] && echo -n ","
    
    ack_timeout=$(uci get acktimeout.$wifi.value 2>/dev/null || echo "null")

    echo -n "\"$wifi\": { \"acktimeout\": $ack_timeout }"
    first=0
done
echo "}"


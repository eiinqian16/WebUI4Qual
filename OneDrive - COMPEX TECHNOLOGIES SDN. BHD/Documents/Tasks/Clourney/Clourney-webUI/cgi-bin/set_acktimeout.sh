#!/bin/sh
echo "Content-Type: text/plain"
echo ""

POST_DATA=$(cat)
echo "Received Data: $POST_DATA" >> /tmp/acktimeout_debug.log  

if [ -z "$POST_DATA" ]; then
    echo "Error: No POST data received" >> /tmp/acktimeout_debug.log
    exit 1
fi

echo "$POST_DATA" | tr '&' '\n' | while IFS='=' read -r name value; do
    echo "Processing: $name = $value" >> /tmp/acktimeout_debug.log  

    if echo "$name" | grep -qE '^wifi[0-9]+' && [ "$value" -ge 64 ] && [ "$value" -le 255 ]; then
        echo "Setting $name to $value" >> /tmp/acktimeout_debug.log
        cfg80211tool "$name" acktimeout "$value"
        uci set acktimeout.$name.value="$value"
    else
        echo "Invalid value for $name: $value" >> /tmp/acktimeout_debug.log
    fi
done

uci commit acktimeout
echo "ACK Timeout done！"


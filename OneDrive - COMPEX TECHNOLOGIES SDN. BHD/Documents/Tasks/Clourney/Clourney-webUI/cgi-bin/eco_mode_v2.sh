#!/bin/sh

echo "Content-Type: application/json"
echo ""

echo "QUERY_STRING: $QUERY_STRING" >&2
action="${1:-$(printf '%s' "$QUERY_STRING" | awk -F'=' '/action=/{print $2}')}"

case "$action" in
    normal)
        /usr/bin/led-ctrl &
        iw wlan0 set txpower fixed 3000
        iw wlan1 set txpower fixed 3000
        logger -t "Switched to Normal Mode"
        echo "{\"status\":\"OK\",\"applied_mode\":\"normal\"}"
        ;;
    eco)
        echo 0 > /sys/class/leds/blue:status/brightness
        echo 0 > /sys/class/leds/red:status/brightness
        echo 0 > /sys/class/leds/green:status/brightness
        killall ctrl-internet-led 2>/dev/null
        killall led-ctrl 2>/dev/null
        iw wlan0 set txpower fixed 1500
        iw wlan1 set txpower fixed 1500
        logger -t "Switched to Eco Mode"
        echo "{\"status\":\"OK\",\"applied_mode\":\"eco\"}"
        ;;
    status)
        if pgrep -x led-ctrl >/dev/null; then
            echo "{\"status\":\"OK\",\"applied_mode\":\"normal\"}"
        else
            echo "{\"status\":\"OK\",\"applied_mode\":\"eco\"}"
        fi
        ;;
    *)
        echo "{\"status\":\"error\",\"error\":\"Invalid mode parameter\"}"
        ;;
esac
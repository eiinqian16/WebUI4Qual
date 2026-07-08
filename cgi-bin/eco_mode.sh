#!/bin/sh

echo "Content-Type: application/json"
echo ""

echo "QUERY_STRING: $QUERY_STRING" >&2
action="${1:-$(printf '%s' "$QUERY_STRING" | awk -F'=' '/action=/{print $2}')}"

case "$action" in
    normal)
        uci set system.@led[0].default='1'
        uci set system.@led[1].default='1'
        uci set system.@led[2].default='1'
        uci commit
        service led reload >&2
        /etc/init.d/cls-leds start
        iw wlan0 set txpower fixed 3000
        iw wlan1 set txpower fixed 3000
        logger -t "Switched to Normal Mode"
        echo "{\"status\":\"OK\",\"applied_mode\":\"normal\"}"
        ;;
    eco)
        uci set system.@led[0].default='0'
        uci set system.@led[1].default='0'
        uci set system.@led[2].default='0'
        uci commit
        service led reload >&2
        killall ctrl-internet-led 2>/dev/null
        iw wlan0 set txpower fixed 1500
        iw wlan1 set txpower fixed 1500
        logger -t "Switched to Eco Mode"
        echo "{\"status\":\"OK\",\"applied_mode\":\"eco\"}"
        ;;
    status)
        led_stat=$(uci get system.@led[0].default 2>/dev/null)
        if [ "$led_stat" = "0" ];then
            echo "{\"status\":\"OK\",\"applied_mode\":\"eco\"}"
        else
            echo "{\"status\":\"OK\",\"applied_mode\":\"normal\"}"
        fi
        ;;
    *)
        echo "{\"status\":\"error\",\"error\":\"Invalid mode parameter\"}"
        ;;
esac
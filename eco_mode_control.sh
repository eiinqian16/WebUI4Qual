action="$1"

if [ -z "$action" ]; then
    echo "Usage: $0 {normal|eco}"
    exit 1
fi

case "$action" in
    normal)
        echo 255 > /sys/class/leds/blue:status/brightness
        echo 255 > /sys/class/leds/red:status/brightness
        echo 255 > /sys/class/leds/green:status/brightness
        led-ctrl &
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
    *)
        echo "{\"status\":\"error\",\"error\":\"Invalid mode parameter\"}"
        ;;
esac
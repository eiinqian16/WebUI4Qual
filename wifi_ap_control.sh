#! /bin/sh

action="$1"

if [ -z "$action" ]; then
    echo "Usage: $0 {enable|disable}"
    exit 1
fi

uci show wireless | while IFS= read -r line; do
    if echo "$line" | grep -q "=wifi-iface"; then
        iface=$(echo "$line" | cut -d. -f2| cut -d= -f1)
        mode=$(uci get wireless."$iface".mode 2>/dev/null)

        if [ "$mode" = "ap" ]; then
            if [ "$action" = "disable" ]; then
                uci set wireless."$iface".disabled='1'
                echo "Disabled $iface (AP mode)"
            elif [ "$action" = "enable" ]; then
                uci set wireless."$iface".disabled='0'
                echo "Enabled $iface (AP mode)"
            else
                echo "Invalid action: $action"
                exit 1
            fi
        fi
    fi
done

uci commit wireless
wifi
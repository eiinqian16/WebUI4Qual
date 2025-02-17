#!/bin/sh
echo "Content-Type: application/json"
echo ""

echo "{"

wifi_devices=$(uci show wireless | grep "=wifi-device" | cut -d. -f2 | cut -d= -f1)
total_devices=$(echo "$wifi_devices" | wc -l)
count=0

for device in $wifi_devices; do
    type=$(uci get wireless.$device.type 2>/dev/null)
    channel=$(uci get wireless.$device.channel 2>/dev/null)
    macaddr=$(uci get wireless.$device.macaddr 2>/dev/null)
    hwmode=$(uci get wireless.$device.hwmode 2>/dev/null)
    disabled=$(uci get wireless.$device.disabled 2>/dev/null)

    iface_json="\"iface\": {\"device\": \"$device\", \"network\": \"\", \"mode\": \"\", \"ssid\": \"\", \"encryption\": \"\"}"

    wifi_ifaces=$(uci show wireless | grep "=wifi-iface" | cut -d. -f2 | cut -d= -f1)
    for iface in $wifi_ifaces; do
        iface_device=$(uci get wireless.$iface.device 2>/dev/null)
        
        if [ "$iface_device" = "$device" ]; then
            network=$(uci get wireless.$iface.network 2>/dev/null)
            mode=$(uci get wireless.$iface.mode 2>/dev/null)
            ssid=$(uci get wireless.$iface.ssid 2>/dev/null)
            encryption=$(uci get wireless.$iface.encryption 2>/dev/null)

            iface_json="\"iface\": {\"device\": \"$device\", \"network\": \"$network\", \"mode\": \"$mode\", \"ssid\": \"$ssid\", \"encryption\": \"$encryption\"}"
        fi
    done

    echo "  \"$device\": {"
    echo "    \"device\": \"$device\","
    echo "    \"type\": \"$type\","
    echo "    \"channel\": \"$channel\","
    echo "    \"macaddr\": \"$macaddr\","
    echo "    \"hwmode\": \"$hwmode\","
    echo "    \"disabled\": \"$disabled\","
    echo "    $iface_json"
    
    count=$((count + 1))
    if [ $count -lt $total_devices ]; then
        echo "  },"
    else
        echo "  }"
    fi
done

echo "}"


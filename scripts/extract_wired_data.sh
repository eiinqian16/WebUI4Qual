#!/bin/sh

# Set content type to json
echo "Content-Type: application/json"
echo ""  # Separate header from body

extract_ifconfig() {
    ifconfig_output=$(ifconfig "$1")
    #lanDev=$(uci get network.lan.device)
    lan_device=$(uci get network.lan.device 2>/dev/null)
    wan_device=$(uci get network.wan.device 2>/dev/null)

    # extract data
    iface=$(echo "$1");
    ip=$(echo "$ifconfig_output" | grep "inet addr" | awk -F':' '{print $2}' | awk '{print $1}'); 
    netmask=$(echo "$ifconfig_output" | grep "Mask"| awk -F':' '{print $4}');
    hwaddr=$(echo "$ifconfig_output" | awk -F 'HWaddr' '{print $2}');
    rxpkt=$(echo "$ifconfig_output" | grep "RX packets:" | awk -F':' '{print $2}' | awk '{print $1}');
    txpkt=$(echo "$ifconfig_output" | grep "TX packets:" | awk -F':' '{print $2}' | awk '{print $1}');
    rxbytes=$(echo "$ifconfig_output" | grep "RX bytes" | awk -F'(' '{print $2}' | awk -F ")" '{print $1}');
    txbytes=$(echo "$ifconfig_output" | grep "TX bytes" | awk -F'(' '{print $2}' | awk -F ")" '{print $1}');
    if [ "$lan_device" = "$1" ]; then
        proto=$(uci get network.lan.proto 2>/dev/null)
        type="LAN"
        gateway=$(echo "")
        bcast=$(ifconfig "$1" | grep "Bcast" | awk -F':' '{print $3}'| awk '{print $1}')
        
    elif [ "$wan_device" = "$1" ]; then
        proto=$(uci get network.wan.proto 2>/dev/null)
        type="WAN"
        gateway=$(ip route | grep "default via" | awk '{print $3}')
        bcast=$(ifconfig "$1" | grep "Bcast" | awk -F':' '{print $3}'| awk '{print $1}')
    else
        #echo "Error: Device $1 not found in LAN or WAN configuration."
        #exit 1
        proto=$(echo "")
        type=$(echo "other")
        gateway=$(echo "")
        bcast=$(echo "")
    fi

    # output as JSON
    json_output="{"
    json_output="${json_output}\"iface\":\"${iface}\""
    [ -n "$hwaddr" ] && json_output="${json_output},\"MAC\":\"${hwaddr}\""
    [ -n "$ip" ] && json_output="${json_output},\"IP\":\"${ip}\""
    [ -n "$bcast" ] && json_output="${json_output},\"bcast\":\"${bcast}\""
    [ -n "$netmask" ] && json_output="${json_output},\"netmask\":\"${netmask}\""
    [ -n "$rxpkt" ] && json_output="${json_output},\"rxpkt\":\"${rxpkt}\""
    [ -n "$txpkt" ] && json_output="${json_output},\"txpkt\":\"${txpkt}\""
    [ -n "$rxbytes" ] && json_output="${json_output},\"rxbytes\":\"${rxbytes}\""
    [ -n "$txbytes" ] && json_output="${json_output},\"txbytes\":\"${txbytes}\""
    [ -n "$proto" ] && json_output="${json_output},\"proto\":\"${proto}\""
    [ -n "$type" ] && json_output="${json_output},\"type\":\"${type}\""
    [ -n "$gateway" ] && json_output="${json_output},\"gateway\":\"${gateway}\""
    json_output="${json_output}}"

    echo "$json_output"
}

dir="/sys/class/net"
json_objects=$(find "$dir" -maxdepth 1 \( -name "br*" -o -name "eth*" -o -name "wan*" \) | while read -r file; do
    filename=$(basename "$file")
    extract_ifconfig "$filename"
done)

joined=$(echo "$json_objects" | tr '\n' ',' | sed 's/,$//')

json_array="[$joined]"

echo "$json_array"
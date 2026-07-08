#!/bin/sh

# Set content type to json
echo "Content-Type: application/json"
echo ""  # Separate header from body

extract_ifconfig() {
    ifconfig_output=$(ifconfig "$1")
    #lanDev=$(uci get network.lan.device)
    lan_device=$(uci get network.lan.device 2>/dev/null)

    wan_device=$(uci get network.wan.device 2>/dev/null)
    if [ -z "$wan_device" ]; then
        wan_device=$(uci get network.wan.ifname 2>/dev/null)
    fi


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
        gateway=""
        bcast=$(ifconfig "$1" | grep "Bcast" | awk -F':' '{print $3}' | awk '{print $1}')
    elif [ "$wan_device" = "$1" ]; then
        proto=$(uci get network.wan.proto 2>/dev/null)
        type="WAN"
        gateway=$(ip route | grep "default via" | awk '{print $3}')
        bcast=$(ifconfig "$1" | grep "Bcast" | awk -F':' '{print $3}' | awk '{print $1}')
    elif [[ "$1" == 3g* ]]; then
        proto=$(uci get network.wan.proto 2>/dev/null)
        type="WAN"
        gateway=$(ip route | grep "default via" | awk '{print $3}')
        bcast=$(ifconfig "$1" | grep "Bcast" | awk -F':' '{print $3}' | awk '{print $1}')
    else
        proto=""
        type="other"
        gateway=""
        bcast=""
    fi

    operator=""
    rat=""

    if [ "$1" = "$cellular_iface" ]; then
        # get operator
        operator=$(echo "$resp" | awk -F',' '/\+COPS:/ {gsub(/"/,"",$3); print $3}')

        if [ -z "$operator" ]; then
            operator="No operator detected or modem not registered"
        fi

        # get 4g or 5g
        rat=$(echo "$resp" | awk -F',' '/\+COPS:/ {print $4}' | tr -d '\r\n ')

        if [ -z "$resp" ]; then
            rat="No RAT found"
        fi
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
    [ -n "$operator" ] && json_output="${json_output},\"operator\":\"${operator}\""
    [ -n "$rat" ] && json_output="${json_output},\"rat\":\"${rat}\""
    json_output="${json_output}}"

    echo "$json_output"
}

get_cellular_iface() {
    modem_block=$(awk '/Quectel/{flag=1} flag; /^$/{flag=0}' /sys/kernel/debug/usb/devices)
    bus=$(grep -m1 "Quectel" -B4 /sys/kernel/debug/usb/devices | grep -m1 "Bus=" | sed -nE 's/.*Bus=0*([0-9]+).*/\1/p')
    lev=$(grep -m1 "Quectel" -B4 /sys/kernel/debug/usb/devices | grep -m1 "Lev=" | sed -nE 's/.*Lev=0*([0-9]+).*/\1/p')
    prnt=$(grep -m1 "Quectel" -B4 /sys/kernel/debug/usb/devices | grep -m1 "Prnt=" | sed -nE 's/.*Prnt=0*([0-9]+).*/\1/p')
    port=$(grep -m1 "Quectel" -B4 /sys/kernel/debug/usb/devices | grep -m1 "Port=" | sed -nE 's/.*Port=0*([0-9]+).*/\1/p')
    driver=$(awk '/Quectel/{flag=1} flag; /^$/{flag=0}' /sys/kernel/debug/usb/devices \
    | grep "Driver=" | grep "cdc" | grep -v "option" -m1 \
    | sed -nE 's/.*Driver=([a-zA-Z0-9_+-]+).*/\1/p')
    id="${bus}-${lev}:${prnt}.${port}"
    iface=$(ls /sys/bus/usb/drivers/$driver/$id/net)
    echo "$iface"
}

dir="/sys/class/net"
MODEM_DEV="/dev/ttyUSB2"

exec 3<> "$MODEM_DEV"
echo -e "AT+COPS?\r" >&3
resp=$(timeout 3 cat <&3 2>/dev/null | grep "+COPS" || true)
exec 3>&-

cellular_iface=$(get_cellular_iface)

json_objects=$(find "$dir" -maxdepth 1 \( -name "br*" -o -name "eth*" -o -name "wan*" -o -name "usb*" \) | while read -r file; do
    filename=$(basename "$file")
    extract_ifconfig "$filename"
done)

joined=$(echo "$json_objects" | tr '\n' ',' | sed 's/,$//')

json_array="[$joined]"

echo "$json_array"

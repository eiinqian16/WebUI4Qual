#!/bin/sh

echo "Content-type: text/plain"
echo ""

#read INPUT
#INPUT="dev=eth0&proto=static&IP=192.168.10.10&Netmask=255.255.0.0&gateway=192.168.10.100&bcast=192.168.10.255&dns1=8.8.8.8&dns2=8.8.4.4"
INPUT="dev=eth1&proto=dhcp"

extract_value() {
    echo "$INPUT" | awk -v key="$1" 'BEGIN{FS="&"} {
        for (i=1; i<=NF; i++) {
            split($i, arr, "=");
            if (arr[1] == key) print arr[2];
        }
    }'
}

# Extract values
dev=$(extract_value "dev")
proto=$(extract_value "proto")
ip=$(extract_value "IP")
netmask=$(extract_value "Netmask")
gateway=$(extract_value "gateway")
bcast=$(extract_value "bcast")
dns1=$(extract_value "dns1")
dns2=$(extract_value "dns2")

# Ensure missing values are set to a default (or empty)
dev=${dev:-""}
proto=${proto:-""}
ip=${ip:-""}
netmask=${netmask:-""}
gateway=${gateway:-""}
bcast=${bcast:-""}
dns1=${dns1:-""}
dns2=${dns2:-""}

# Find LAN index for `br-lan`
idx=$(uci show network | grep "network.@device\[.*\].name='br-lan'" | sed -E "s/.*@device\[([0-9]+)\].*/\1/")
uci del network.@device["$idx"].ports 2>/dev/null

# Add eth devices except the selected WAN device
dir="/sys/class/net"
find "$dir" -maxdepth 1 -name "eth*" | while read -r file; do
    filename=$(basename "$file")
    if [ "$filename" != "$dev" ]; then
        uci add_list network.@device["$idx"].ports="$filename"
    fi
done

# Configure WAN
if ! uci show network | grep -q '^network\.wan=interface'; then
    uci set network.wan=interface
fi

uci set network.wan.device="$dev"
uci set network.wan.proto="$proto"

if [ "$proto" = "static" ]; then
    uci set network.wan.ipaddr="$ip"
    uci set network.wan.netmask="$netmask"
    uci set network.wan.gateway="$gateway"
    uci set network.wan.broadcast="$bcast"
    
    # Configure DNS
    uci del network.wan.dns 2>/dev/null
    [ -n "$dns1" ] && uci add_list network.wan.dns="$dns1"
    [ -n "$dns2" ] && uci add_list network.wan.dns="$dns2"
else
    # If DHCP, remove any previous static configuration
    uci -q del network.wan.ipaddr
    uci -q del network.wan.netmask
    uci -q del network.wan.gateway
    uci -q del network.wan.broadcast
    uci -q del network.wan.dns
fi

uci commit
/etc/init.d/network reload


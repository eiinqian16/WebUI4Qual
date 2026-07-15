#!/bin/sh

echo "Content-type: text/plain"
echo ""

read INPUT
#INPUT="dev=eth0&proto=static&IP=192.168.10.10&Netmask=255.255.0.0&gateway=192.168.10.100&bcast=192.168.10.255&dns1=8.8.8.8&dns2=8.8.4.4"
#INPUT="dev=eth1&proto=dhcp"

extract_value() {
    echo "$INPUT" | awk -v key="$1" 'BEGIN{FS="&"} {
        for (i=1; i<=NF; i++) {
            split($i, arr, "=");
            if (arr[1] == key) {
                # URL-decode the value
                gsub(/%2F/, "/", arr[2]);
                gsub(/%3A/, ":", arr[2]);
                print arr[2];
            }
        }
    }'
}

# Extract values
proto=$(extract_value "proto")
dev=$(extract_value "dev")  # For DHCP/Static
lteDev=$(extract_value "lteDev")  # For LTE
ip=$(extract_value "IP")
netmask=$(extract_value "Netmask")
gateway=$(extract_value "gateway")
bcast=$(extract_value "bcast")
dns1=$(extract_value "dns1")
dns2=$(extract_value "dns2")
lteService=$(extract_value "lteService")
lteApn=$(extract_value "lteApn")
ltePin=$(extract_value "ltePin")
lteDial=$(extract_value "lteDial")
lteSimSlot=$(extract_value "lteSimSlot")


# Defaults for LTE parameters
lteDev=${lteDev:-""}
lteService=${lteService:-""}
lteApn=${lteApn:-""}
ltePin=${ltePin:-""}
lteDial=${lteDial:-""}
lteSimSlot=${lteSimSlot:-""}

# Values are set to a default (or empty)
dev=${dev:-""}
proto=${proto:-""}
ip=${ip:-""}
netmask=${netmask:-""}
gateway=${gateway:-""}
bcast=${bcast:-""}
dns1=${dns1:-""}
dns2=${dns2:-""}

# Validate LTE required fields
if [ "$proto" = "lte" ]; then
    if [ -z "$lteApn" ] || [ -z "$lteDev" ]; then
        echo "APN and Modem Device are required for LTE configuration."
        exit 1
    fi
fi

# Find LAN index for `br-lan`
idx=$(uci show network | grep "network.@device\[.*\].name='br-lan'" | sed -E "s/.*@device\[([0-9]+)\].*/\1/")
uci del network.@device["$idx"].ports 2>/dev/null

# Capture existing WAN device before reconfiguration
existing_wan_dev=$(uci get network.wan.device 2>/dev/null)

dir="/sys/class/net"
find "$dir" -maxdepth 1 -name "eth*" | while read -r file; do
    filename=$(basename "$file")

    # Skip WAN device in dhcp/static mode
    if { [ "$proto" = "dhcp" ] || [ "$proto" = "static" ]; } && [ "$filename" = "$dev" ]; then
        continue
    fi

    # Dynamic check to avoid duplicates
    current_ports=$(uci get network.@device["$idx"].ports 2>/dev/null)
    if ! echo "$current_ports" | grep -wq "$filename"; then
        uci add_list network.@device["$idx"].ports="$filename"
    fi
done

# If switching WAN devices, ensure previous WAN is removed
if [ "$proto" != "lte" ] && [ -n "$existing_wan_dev" ] && [ "$existing_wan_dev" != "$dev" ]; then
    uci del network.wan
fi

# Explicitly add back the previous WAN device (if not eth* and not the new dev)
# Skip this step if proto is "none"
if [ "$proto" != "none" ] && [ -n "$existing_wan_dev" ] && [ "$existing_wan_dev" != "$dev" ]; then
    if ! echo "$existing_wan_dev" | grep -q "^eth"; then
        uci add_list network.@device["$idx"].ports="$existing_wan_dev"
    fi
fi

# Configure WAN
if ! uci show network | grep -q '^network\.wan=interface'; then
    uci set network.wan=interface
fi

if [ "$proto" != "lte" ]; then
    uci set network.wan.device="$dev"
else
    uci set network.wan.device="$lteDev"
fi

uci set network.wan.proto="$proto"

case "$proto" in
    "static")
        uci set network.wan.ipaddr="$ip"
        uci set network.wan.netmask="$netmask"
        [ -n "$gateway" ] && uci set network.wan.gateway="$gateway" || uci -q del network.wan.gateway
        [ -n "$bcast" ] && uci set network.wan.broadcast="$bcast" || uci -q del network.wan.broadcast
        uci del network.wan.dns 2>/dev/null
        [ -n "$dns1" ] && uci add_list network.wan.dns="$dns1"
        [ -n "$dns2" ] && uci add_list network.wan.dns="$dns2"
        ;;
    "dhcp")
        uci -q del network.wan.ipaddr
        uci -q del network.wan.netmask
        uci -q del network.wan.gateway
        uci -q del network.wan.broadcast
        uci -q del network.wan.dns
        ;;
    "lte")
        wifi down     
        uci set network.wan.proto="3g"
        uci set network.wan.ipv6='auto'
        uci set network.wan.device="$lteDev"
        uci set network.wan.service="$lteService"
        uci set network.wan.apn="$lteApn"
        uci set network.wan.pincode="$ltePin"
        uci set network.wan.dialnumber="$lteDial"
        if [ "$lteSimSlot" = "sim2" ]; then
            uci set network.wan.simsel=1
            reboot_required=1
        elif [ "$lteSimSlot" = "sim1" ]; then
            uci -q del network.wan.simsel
            reboot_required=1
        fi
        ;;
    "none")
        existing_wan_dev=$(uci get network.wan.device 2>/dev/null)
        uci del network.wan
       # Only restore previous WAN dev if it's an eth* and not already present
        if [ -n "$existing_wan_dev" ] && [ "$existing_wan_dev" != "$dev" ]; then
            if echo "$existing_wan_dev" | grep -q "^eth"; then
                current_ports=$(uci get network.@device["$idx"].ports 2>/dev/null)
                if ! echo "$current_ports" | grep -wq "$existing_wan_dev"; then
                    uci add_list network.@device["$idx"].ports="$existing_wan_dev"
                fi
            fi
        fi
        ;;
esac

uci commit network
/etc/init.d/network reload

wifi up

if [ "$reboot_required" -eq 1 ]; then
    echo "Rebooting due to SIM slot change..."
    reboot
    exit 0
fi

echo "Configuration saved successfully"
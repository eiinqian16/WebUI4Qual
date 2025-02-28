#!/bin/sh

echo "Content-type: text/plain"
echo ""

read INPUT
#INPUT="isEnabled=server&startIp=192.168.1.55&endIp=192.168.1.105&leasetime=13"
#INPUT="isEnabled=disable"

extract_value() {
    echo "$INPUT" | awk -v key="$1" 'BEGIN{FS="&"} {
        for (i=1; i<=NF; i++) {
            split($i, arr, "=");
            if (arr[1] == key) print arr[2];
        }
    }'
}

isEnabled=$(extract_value "isEnabled"); 
startIp=$(extract_value "startIp");
start=$(echo "$startIp" | awk -F'.' '{print $4}');
endIp=$(extract_value "endIp");
end=$(echo "$endIp" | awk -F'.' '{print $4}');
lease=$(extract_value "leasetime");
if [ -n "$end" ] && [ -n "$start" ]; then
    lim=$(($end - $start))
fi
lease_h="${lease}h"

if [ "$isEnabled" = "disable" ]; then
    uci set dhcp.lan.dhcpv4="$isEnabled"
elif [ "$isEnabled" = "server" ]; then
    uci set dhcp.lan.dhcpv4="$isEnabled"
    uci set dhcp.lan.start="$start"
    uci set dhcp.lan.limit="$lim"
    uci set dhcp.lan.leasetime="$lease_h"
else
    echo "Unknown configuration"
fi
echo "$isEnabled"
echo "$startIp"
echo "$start"
echo "$endIp"
echo "$end"
echo "$lease"
echo "$lim"
echo "$lease_h"
uci commit
#reboot
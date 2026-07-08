#!/bin/sh

echo "Content-type: text/plain"
echo ""

read INPUT
#INPUT="IP=192.168.1.10&Netmask=255.255.0.0&gateway=192.168.1.100"
#INPUT="IP=192.168.1.10&Netmask=255.255.0.0"
#echo "$INPUT"

ip=$(echo "$INPUT" | grep "IP" | awk -F'=' '{print $2}' | awk -F'&' '{print $1}');
mask=$(echo "$INPUT" | grep "Netmask" | awk -F'=' '{print $3}' | awk -F'&' '{print $1}');
gateway=$(echo "$INPUT" | grep "gateway" | awk -F'=' '{print $4}');

echo "$mask"
echo "$gateway"
uci set network.lan.ipaddr="$ip"
uci set network.lan.netmask="$mask"
if [ -n "$gateway" ]; then
    uci set network.lan.gateway="$gateway"
    #echo "Setting gateway ip"
fi
uci commit
/etc/init.d/network reload
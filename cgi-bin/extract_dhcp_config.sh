#!/bin/sh

# Set content type to json
echo "Content-Type: application/json"
echo ""

dhcpv4=$(uci get dhcp.lan.dhcpv4);
if [ "$dhcpv4" = "server" ]; then
    isEnabled="Enabled"
    lanIp=$(uci get network.lan.ipaddr | awk -F'.' '{print $1 "." $2 "." $3}');
    startIp=$(uci get dhcp.lan.start);
    ipLim=$(uci get dhcp.lan.limit);
    endIp=$(($startIp + $ipLim))
    leasetime=$(uci get dhcp.lan.leasetime | sed 's/[^0-9]*//g');
elif [ "$dhcpv4" = "disable" ]; then
    isEnabled="Disabled"
else
    echo "Unknown configuration!"
fi

json_output="{"
json_output="${json_output}\"startIp\":\"${lanIp}.${startIp}\""
[ -n "$endIp" ] && json_output="${json_output},\"endIp\":\"${lanIp}.${endIp}\""
[ -n "$leasetime" ] && json_output="${json_output},\"leasetime\":\"${leasetime}\""
[ -n "$isEnabled" ] && json_output="${json_output},\"isEnabled\":\"${isEnabled}\""

json_output="${json_output}}"

echo "$json_output"
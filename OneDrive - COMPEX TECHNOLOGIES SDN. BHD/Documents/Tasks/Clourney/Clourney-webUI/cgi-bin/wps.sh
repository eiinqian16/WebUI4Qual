#!/bin/sh

echo "Content-Type: application/json"
echo ""

read INPUT

parse_query() {
    local input="$1"
    local key="$2"
    echo "$input" | grep -o "$key=[^&]*" | cut -d= -f2 | sed 's/%3A/:/g' | tr -d '\r\n '
}

role=$(parse_query "$INPUT" "role")

if [ -z "$role" ]; then
    echo '{"status":"error","message":"Missing role parameter"}'
    exit 1
fi

if [ "$role" = "agent" ]; then
    # Assuming wlan1-1 is the correct interface for agent mode WPS
    wpa_cli -i wlan1-1 wps_pbc multi_ap=1
    if [ $? -eq 0 ]; then
        echo '{"status":"success","message":"WPS PBC initiated for Agent"}'
    else
        echo '{"status":"error","message":"Failed to initiate WPS PBC for Agent"}'
    fi
elif [ "$role" = "controller" ]; then
    # Assuming wlan1 is the correct interface for controller mode WPS
    hostapd_cli -i wlan1 wps_pbc
    if [ $? -eq 0 ]; then
        echo '{"status":"success","message":"WPS PBC initiated for Controller"}'
    else
        echo '{"status":"error","message":"Failed to initiate WPS PBC for Controller"}'
    fi
else
    echo '{"status":"error","message":"Invalid role specified for WPS"}'
fi

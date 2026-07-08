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
action=$(parse_query "$INPUT" "action") # Not directly used in this specific request, but good to parse.

if [ -z "$role" ]; then
    echo '{"status":"error","message":"Missing role parameter"}'
    exit 1
fi

if [ "$role" = "controller" ]; then
    uci set cls-mesh.default.mode=controller
    uci commit cls-mesh
    /etc/init.d/cls-mesh restart
    cp /etc/ui-config/wireless-meshAP /etc/config/wireless
    /etc/init.d/network restart
    echo '{"status":"success","message":"EZMesh role set to controller"}'
elif [ "$role" = "agent" ]; then
    uci set cls-mesh.default.mode=agent
    uci commit cls-mesh
    /etc/init.d/cls-mesh restart
    cp /etc/ui-config/wireless-meshAgent /etc/config/wireless
    /etc/init.d/network restart
    echo '{"status":"success","message":"EZMesh role set to agent"}'
elif [ "$role" = "none" ]; then
    uci set cls-mesh.default.mode=none
    uci commit cls-mesh
    /etc/init.d/cls-mesh restart
    cp /etc/ui-config/wireless-normal /etc/config/wireless
    /etc/init.d/network restart
    echo '{"status":"success","message":"EZMesh disabled, role set to none"}'
else
    echo '{"status":"error","message":"Invalid role specified"}'
fi
else
    echo '{"status":"error","message":"Invalid role specified"}'
fi

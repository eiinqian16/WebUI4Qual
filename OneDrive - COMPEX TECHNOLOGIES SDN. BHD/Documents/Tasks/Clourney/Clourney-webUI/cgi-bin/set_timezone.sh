#!/bin/sh

read -r POST_DATA

TIMEZONE=$(echo "$POST_DATA" | sed 's/.*"timezone":"\([^"]*\)".*/\1/')
ZONE_NAME=$(echo "$POST_DATA" | sed 's/.*"zone_name":"\([^"]*\)".*/\1/')

if [ -z "$TIMEZONE" ] || [ "$TIMEZONE" = "$POST_DATA" ]; then
    echo "Content-Type: application/json"
    echo ""
    echo '{"success":"false", "error":"Missing or invalied timezone field"}'
    exit 1
fi

if [ -z "$ZONE_NAME" ] || [ "$ZONE_NAME" = "$POST_DATA" ]; then
    echo "Content-Type: application/json"
    echo ""
    echo '{"success":"false", "error":"Missing or invalid zone name field"}'
    exit 1
fi

uci set system.@system[0].timezone="$TIMEZONE"
uci set system.@system[0].zonename="$ZONE_NAME"
uci commit system
/etc/init.d/system restart

echo "Content-Type: application/json"
echo ""
printf '{"success":"true","timezone":"%s", "zone_name":"%s"}' "$TIMEZONE" "$ZONE_NAME"
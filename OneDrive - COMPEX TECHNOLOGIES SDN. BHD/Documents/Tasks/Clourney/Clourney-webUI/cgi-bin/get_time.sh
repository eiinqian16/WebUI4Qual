#!/bin/sh

echo "Content-Type: application/json"
echo ""

EPOCH=$(date +%s)
ZONE_NAME=$(uci -q get system.@system[0].zonename 2>/dev/null | sed 's/ /_/g')

if [ -n "$ZONE_NAME" ]; then
    TZ_NAME="$ZONE_NAME"
else
    TZ_OFFSET=$(date +%z)
    TZ_SIGN=${TZ_OFFSET%????}
    TZ_HHMM=${TZ_OFFSET#?}
    TZ_HOUR=${TZ_HHMM%??}
    TZ_MINUTE=${TZ_HHMM#??}
    TZ_HOUR=$(printf '%s' "$TZ_HOUR" | sed 's/^0*//')

    if [ -z "$TZ_HOUR" ]; then
        TZ_HOUR=0
    fi

    if [ "$TZ_HOUR" = "0" ] && [ "$TZ_MINUTE" = "00" ]; then
        TZ_NAME="UTC"
    elif [ "$TZ_MINUTE" = "00" ]; then
        if [ "$TZ_SIGN" = "+" ]; then
            TZ_NAME="Etc/GMT-$TZ_HOUR"
        else
            TZ_NAME="Etc/GMT+$TZ_HOUR"
        fi
    else
        TZ_NAME="UTC"
    fi
fi

cat <<EOF
{
    "epoch": $EPOCH,
    "timezone": "$TZ_NAME"
}
EOF

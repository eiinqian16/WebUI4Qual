#!/bin/sh

echo "Content-Type: application/json"
echo ""

read INPUT

type=$(echo "$INPUT" | grep -o 'type=[^&]*' | cut -d= -f2 | tr -d '\r\n ')
bands=$(echo "$INPUT" | grep -o 'bands=[^&]*' | cut -d= -f2 | sed 's/%3A/:/g' | tr -d '\r\n ')

STATS_FILE="/tmp/lte_stats"
MODEM_DEV="/dev/ttyUSB2"

at_cmd() {
    local cmd="$1"
    local timeout="${2:-2}"
    local response=""

    # Use lock to prevent collision with other scripts
    touch /tmp/modem.lock
    exec 8>/tmp/modem.lock
    flock -x 8

    if exec 3<> "$MODEM_DEV"; then
        # Drain buffer
        read -t 1 <&3
        printf "%s\r\n" "$cmd" >&3
        response=$(timeout "$timeout" cat <&3 2>/dev/null | tr -d '\r')
        exec 3>&-
    fi

    flock -u 8
    exec 8>&-
    echo "$response"
}


if [ -z "$type" ] || [ -z "$bands" ]; then
    echo "{\"status\":\"error\", \"message\":\"Invalid input. Type:[$type] Bands:[$bands]\"}"
    exit 1
fi

COMMAND=$(printf "AT+QNWPREFCFG=\"%s\",%s\r" "$type" "$bands")
resp=$(at_cmd "$COMMAND" 3)

if echo "$resp" | grep -q "OK"; then
    # Give the modem 2 seconds to transition frequencies naturally
    sleep 2
    
    # Query the modem for the ACTUAL current connection
    actual_info=$(at_cmd "AT+QENG=\"servingcell\"" 2)
    
    # Extract the band (e.g., 28) from "+QENG: \"servingcell\",...,EUTRAN-BAND28,..."
    active_band=$(echo "$actual_info" | grep '^+QENG: "servingcell"' | awk -F ',' '{print $10}' | tr -dc '0-9-')
    
    # If not registered yet, default to the requested band for the UI
    [ -z "$active_band" ] && active_band="$bands"

    # Update the stats file for the WebUI display
    if [ -f "$STATS_FILE" ]; then
        sed -i "s/\"band\":\"[^\"]*\"/\"band\":\"$active_band\"/" "$STATS_FILE"
    fi
    
    echo "{\"status\":\"success\", \"active\":\"$active_band\", \"message\":\"Band mask updated live.\"}"
else
    err_detail=$(echo "$resp" | tr -d '\r\n' | sed 's/"/\\"/g')
    echo "{\"status\":\"error\", \"message\":\"Modem Rejected: $err_detail\"}"
fi
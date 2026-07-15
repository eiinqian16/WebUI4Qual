#!/bin/sh

# Set the correct content type for WebUI
echo "Content-Type: application/json"
echo ""

# Read the POST data
read INPUT

# Parse parameters
type=$(echo "$INPUT" | grep -o 'type=[^&]*' | cut -d= -f2 | tr -d '\r\n ')
bands=$(echo "$INPUT" | grep -o 'bands=[^&]*' | cut -d= -f2 | sed 's/%3A/:/g' | tr -d '\r\n ')

MODEM_DEV="/dev/ttyUSB2"
STATS_FILE="/tmp/lte_stats"

at_cmd() {
    local cmd="$1"
    local timeout="${2:-3}"
    local response=""

    touch /tmp/modem.lock
    exec 8>/tmp/modem.lock
    flock -x 8

    if exec 3<> "$MODEM_DEV"; then
        # Quick flush
        read -t 0.2 <&3
        printf "%s\r\n" "$cmd" >&3
        response=$(timeout "$timeout" cat <&3 2>/dev/null | tr -d '\r')
        exec 3>&-
    fi

    flock -u 8
    exec 8>&-
    echo "$response"
}

if [ -z "$bands" ]; then
    echo "{\"status\":\"error\", \"message\":\"No bands selected\"}"
    exit 1
fi

# Calculate Hex Mask
hex_mask=$(echo "$bands" | awk -F':' '{
    mask = 0;
    for(i=1; i<=NF; i++) {
        b = $i; gsub(/[^0-9]/, "", b);
        if (b > 0) {
            mask = or(mask, lshift(1, b-1));
        }
    }
    printf "0x%016X", mask
}')

# ---------------------------------------------------------
# APPLY LOCK ONLY (No Reboot, No Toggle)
# ---------------------------------------------------------
COMMAND="AT+CNBP=0X0002000004400180,$hex_mask"
resp=$(at_cmd "$COMMAND" 3)

if echo "$resp" | grep -q "OK"; then
    # Give the modem 2 seconds to transition frequencies naturally
    sleep 2
    
    # Query the modem for the ACTUAL current connection
    actual_info=$(at_cmd "AT+CPSI?" 2)
    
    # Extract the band (e.g., 28) from "+CPSI: ...,EUTRAN-BAND28,..."
    active_band=$(echo "$actual_info" | grep '^+CPSI:' | awk -F',' '{print $7}' | sed 's/.*BAND//' | tr -dc '0-9')
    
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
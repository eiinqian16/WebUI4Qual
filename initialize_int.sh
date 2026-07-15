#! /bin/sh
MODEM_DEV="/dev/ttyUSB2"

at_cmd() {
    local cmd="$1"
    local timeout="${2:-5}"
    local response=""
    
    [ -c "$MODEM_DEV" ] || return 1
    
    exec 3<> "$MODEM_DEV" 2>/dev/null || return 1
    printf "%s\r\n" "$cmd" >&3
    response=$(timeout "$timeout" cat <&3 2>/dev/null | tr -d '\r')
    exec 3>&-
    
    echo "$response"
    return 0
}

at_cmd "AT+QMAPWAC=1" 3 > /dev/null
    
# Restart modem to apply settings
echo "Restarting modem to apply settings..."
at_cmd "AT+CFUN=1,1" 3 > /dev/null
sleep 10
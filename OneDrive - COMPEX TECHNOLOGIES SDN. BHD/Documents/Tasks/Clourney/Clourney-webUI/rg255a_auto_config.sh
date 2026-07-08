#!/bin/sh

MODEM_DEV="/dev/ttyUSB2"
APN_DB="/www/webUI/db/apn-db.json"
LOG_FILE="/tmp/auto_config.log"

log() { 
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Clean AT command
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

# AT command with retry logic
at_cmd_retry() {
    local cmd="$1"
    local timeout="${2:-5}"
    local max_retries=3
    local retry=0
    local response=""
    
    while [ $retry -lt $max_retries ]; do
        response=$(at_cmd "$cmd" "$timeout")
        
        if [ -n "$response" ]; then
            echo "$response"
            return 0
        fi
        
        retry=$((retry + 1))
        sleep 2
    done
    
    return 1
}

# Wait for SIM to be ready
wait_for_sim_ready() {
    local max_wait=30
    local elapsed=0
    
    while [ $elapsed -lt $max_wait ]; do
        local cpin=$(at_cmd "AT+CPIN?" 3)
        
        if echo "$cpin" | grep -q "READY"; then
            return 0
        fi
        
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    return 1
}

# Wait for serving cell
wait_for_serving_cell() {
    local max_scans=20
    local scan_attempt=0
    
    log "Waiting for modem to find a serving cell..."
    
    while [ $scan_attempt -lt $max_scans ]; do
        scan_attempt=$((scan_attempt + 1))
        
        local serving=$(at_cmd_retry 'AT+QENG="servingcell"' 5)
        
        # Check if searching
        if echo "$serving" | grep -q '"SEARCH"'; then
            log "Attempt $scan_attempt/$max_scans: Modem is searching for network..."
            sleep 4
            continue
        fi
        
        # Check if we have a valid serving cell
        if echo "$serving" | grep -q '"servingcell"'; then
            local mcc=$(echo "$serving" | awk -F ',' '/"servingcell"/ {print $5}' | tr -d '\n\r ')
            
            if [ -n "$mcc" ] && [ "$mcc" != " " ] && [ "$mcc" -ge 100 ] 2>/dev/null; then
                log "Serving cell found with MCC: $mcc"
                echo "$serving"
                return 0
            fi
        fi
        
        sleep 3
    done
    
    log "ERROR: Modem failed to find a network after $max_scans attempts"
    return 1
}

check_internet() {
    local target_iface=$(get_iface)
    [ -n "$target_iface" ] && ping -I "$target_iface" -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 && return 0
    ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1
}

is_pdp_active() {
    local resp=$(at_cmd "AT+CGACT?" 3)
    echo "$resp" | grep -q "+CGACT: 1,1"
}

enable_pdp() {
    at_cmd 'AT+CGACT=1,1' 5
}

disable_data_call() {
    at_cmd 'AT+QNETDEVCTL=0,1,1' 3
}

set_data_call() {
    at_cmd 'AT+QNETDEVCTL=3,1,1' 5
}

get_iface() {
    for i in /sys/class/net/*; do
        dev=$(basename "$i")
        path=$(readlink -f "$i/device" 2>/dev/null)
        if echo "$path" | grep -qE "usb|cdc|qmi|mbim|rndis"; then
            echo "$dev"
        fi
    done
}

setup_iface() {
    iface=$(get_iface)
    if [ -z "$(uci get network.wan 2>/dev/null)" ]; then
        uci set network.wan=interface
    fi

    uci set network.wan.device="$iface"
    uci set network.wan.proto="dhcp"
    uci set firewall.@zone[1].input=ACCEPT
    uci set firewall.@zone[1].forward=ACCEPT
    uci commit network
    uci commit firewall
    /etc/init.d/firewall restart
    log "Restarting network service..."
    /etc/init.d/network restart
    echo '{"status":"success","iface":"'$iface'"}'
}

# Configure APN and network settings
configure_network() {
    log "Configuring network settings..."
    
    # Wait for serving cell
    local serving=$(wait_for_serving_cell)
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to find serving cell"
        return 1
    fi
    
    # Extract network info
    local mcc=$(echo "$serving" | awk -F ',' '/"servingcell"/ {print $5}' | tr -d '\n\r ')
    local mnc=$(echo "$serving" | awk -F ',' '/"servingcell"/ {print $6}' | tr -d '\n\r ')
    local rat=$(echo "$serving" | awk -F ',' '/"servingcell"/ {print $3}' | awk -F '"' '{print $2}' | tr -d '\n\r ')
    
    local plmn="${mcc}${mnc}"
    
    log "Detected PLMN: $plmn, RAT: $rat"
    
    # Get APN from database
    local apn=""
    if [ -f "$APN_DB" ]; then
        apn=$(jsonfilter -i "$APN_DB" -e "@[\"$plmn\"].APNs.$rat.apn" 2>/dev/null)
        
        # Try alternative RATs if not found
        if [ -z "$apn" ]; then
            log "No APN for RAT: $rat, trying alternatives..."
            for alt_rat in "LTE" "WCDMA" "NR5G" "GSM"; do
                apn=$(jsonfilter -i "$APN_DB" -e "@[\"$plmn\"].APNs.$alt_rat.apn" 2>/dev/null)
                if [ -n "$apn" ]; then
                    log "Found APN using RAT: $alt_rat"
                    break
                fi
            done
        fi
    fi
    
    # Use default if still not found
    if [ -z "$apn" ]; then
        apn="internet"
        log "Using default APN: $apn"
    else
        log "Using APN from database: $apn"
    fi
    
    # Set PDP context
    log "Setting APN: $apn for PLMN: $plmn"
    local cgdcont_resp=$(at_cmd "AT+CGDCONT=1,\"IPV4V6\",\"$apn\"" 5)
    
    if echo "$cgdcont_resp" | grep -q "OK"; then
        log "APN configured successfully"
    else
        log "WARNING: APN configuration may have failed"
    fi
    
    # Enable dial up
    at_cmd "AT+QNETDEVCTL=3,1,1" 3 > /dev/null
    
    # Restart modem to apply settings
    log "Restarting modem to apply settings..."
    at_cmd "AT+CFUN=1,1" 3 > /dev/null
    
    sleep 10

    setup_iface
    
    return 0
}

# Main function
main() {
    log "========================================="
    log "Starting Auto Configuration"
    log "========================================="
    
    # Check modem device exists
    if [ ! -c "$MODEM_DEV" ]; then
        log "ERROR: Modem device not found: $MODEM_DEV"
        exit 1
    fi
    
    # Configure network
    if configure_network; then
        log "Network configuration completed"
    else
        log "WARNING: Network configuration had issues"
    fi
    
    # Post-configuration internet verification and recovery
    log "Verifying internet connection..."
    sleep 10

    if ! check_internet; then
        log "No internet connection detected. Checking PDP status..."
        if ! is_pdp_active; then
            log "PDP Context is not active. Enabling PDP context..."
            enable_pdp
            sleep 2
        fi
        log "Recycling data call..."
        disable_data_call
        sleep 2
        set_data_call
        /etc/init.d/network restart
    fi

    log "========================================="
    log "Auto Configuration Complete"
    log "Active Slot: $final_slot"
    
    # Show summary
    if [ -f /tmp/modem_iccid_1 ]; then
        log "Slot 1: $(cat /tmp/modem_iccid_1)"
    fi
    if [ -f /tmp/modem_iccid_2 ]; then
        log "Slot 2: $(cat /tmp/modem_iccid_2)"
    fi
    
    log "========================================="
}

# Run main
main
exit 0
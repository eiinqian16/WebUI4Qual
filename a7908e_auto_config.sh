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
    /etc/init.d/network restart
    echo '{"status":"success","iface":"'$iface'"}'
}

check_internet() {
    log "Checking internet connectivity..."
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log "Internet connection: OK"
        return 0
    fi
    log "Internet connection: FAILED"
    return 1
}

wait_for_modem_reboot() {
    log "Waiting for modem to reboot and re-enumerate..."
    # Give the kernel time to disconnect the device node
    sleep 5
    
    local timeout=60
    local elapsed=0
    while [ ! -c "$MODEM_DEV" ] && [ $elapsed -lt $timeout ]; do
        sleep 2
        elapsed=$((elapsed + 2))
    done

    if [ -c "$MODEM_DEV" ]; then
        log "Modem device detected. Waiting for internal firmware boot..."
        sleep 10
        return 0
    fi
    
    log "ERROR: Modem device $MODEM_DEV did not reappear after ${timeout}s"
    return 1
}

check_ecm() {
    local ecm_status=$(at_cmd "AT+usbnet?" 3)
    
    if echo "$ecm_status" | grep -q "+USBNET: ecm"; then
        log "ECM mode is already active"
        return 0
    else
        log "Configuring ECM mode... modem will reboot"
        at_cmd "AT+USBNET=ecm" 3 > /dev/null
        
        if wait_for_modem_reboot; then
            wait_for_sim_ready
            return 0
        fi
        return 1
    fi

    setup_iface
}

log "Starting A7908E Auto Configuration..."
if check_ecm; then
    check_internet
fi
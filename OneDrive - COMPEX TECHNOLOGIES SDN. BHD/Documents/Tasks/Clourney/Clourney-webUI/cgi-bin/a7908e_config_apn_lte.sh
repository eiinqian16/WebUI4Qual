#!/bin/sh

echo "Content-type: text/plain"
echo "" 

read INPUT

MODEM_DEV="/dev/ttyUSB2"
LOG_FILE="/tmp/a7908e_config.log"

if [ -z "$MODEM_DEV" ]; then
    echo '{"error":"No modem found"}'
    exit 1
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

at_cmd() {
    local cmd="$1"
    local timeout="${2:-2}"
    local resp=""

    # Use lock to prevent collision with other scripts
    touch /tmp/modem.lock
    exec 8>/tmp/modem.lock
    flock -x 8

    if exec 3<> "$MODEM_DEV"; then
        # Drain buffer
        read -t 1 <&3
        printf "%s\r\n" "$cmd" >&3
        resp=$(timeout "$timeout" cat <&3 2>/dev/null | tr -d '\r')
        exec 3>&-
    fi

    flock -u 8
    exec 8>&-
    echo "$resp"
}

extract_value() {
     echo "$INPUT" | awk -v key="$1" 'BEGIN{FS="&"} {
        for (i=1; i<=NF; i++) {
            split($i, arr, "=");
            if (arr[1] == key) {
                gsub(/%2F/, "/", arr[2]);
                gsub(/%3A/, ":", arr[2]);
                print arr[2];
            }
        }
    }'   
}

proto=$(extract_value "proto")
apn=$(extract_value "apn")
slot=$(extract_value "slot")
service=$(extract_value "service")

proto=${proto:-""}
apn=${apn:-""}
slot=${slot:-""}
service=${service:-""}

get_net() {
    local resp=$(at_cmd 'AT+USBNET?' 3)
    if echo "$resp" | grep -q "ecm"; then
        echo "1"
    else
        echo "0"
    fi
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

get_cur_slot() {
    if [ -d "/sys/class/gpio/gpio22" ]; then
        local val=$(cat /sys/class/gpio/gpio22/value 2>/dev/null)
        [ "$val" = "0" ] && echo 1 || echo 2
    else
        echo 1
    fi
}

set_sim_slot() {
    local target_slot="$1"
    [ -z "$target_slot" ] && return 0

    local val=$([ "$target_slot" = "1" ] && echo 0 || echo 1)
    
    if [ ! -d "/sys/class/gpio/gpio22" ]; then
        echo 22 > /sys/class/gpio/export 2>/dev/null
        echo out > /sys/class/gpio/gpio22/direction 2>/dev/null
    fi
    
    echo "$val" > /sys/class/gpio/gpio22/value
    log "Switched SIM slot to $target_slot via GPIO 22"
    
    at_cmd "AT+CFUN=1,1" 3 > /dev/null
    sleep 10
    return 0
}

set_mode_pref() {
    local pref="$1"
    [ -z "$pref" ] && return 0

    local cmd_val=2
    [ "$pref" = "lte" ] && cmd_val=38

    log "Setting mode preference to $pref (AT+CNMP=$cmd_val)"
    local resp=$(at_cmd "AT+CNMP=$cmd_val" 3)
    if echo "$resp" | grep -q "OK"; then
        log "Mode preference set successfully"
        return 0
    else
        log "Error: Failed to set mode preference. Response: $resp"
        return 1
    fi
}

set_ecm() {
    log "Setting modem to ECM mode (AT+USBNET=ecm)"
    at_cmd 'AT+USBNET=ecm' 3
    sleep 10
}

set_data_call() {
    log "Activating PDP context 1"
    enable_pdp
}

disable_data_call() {
    log "Deactivating PDP context 1"
    at_cmd 'AT+CGACT=0,1' 3
}

set_pdp_context() {
    local apn="$1"
    log "Configuring PDP Context 1 with APN: $apn"
    local resp=$(at_cmd "AT+CGDCONT=1,\"IPV4V6\",\"${apn}\"")

    if echo "$resp" | grep -q "OK"; then
        log "PDP Context configured successfully"
        echo '{"set_pdp_context_result":"OK"}'
        return 0
    else
        log "Error: PDP Context configuration failed. Response: $resp"
        echo '{"set_pdp_context_error":"PDP config failed"}'
        echo "$resp"
        return 1
    fi
}

enable_pdp() {
    local resp=$(at_cmd 'AT+CGACT=1,1' 5)

    if echo "$resp" | grep -q "OK"; then
        return 0
    else
        echo '{"enable_pdp_error":"PDP config failed"}'
        echo "$resp"
        return 1
    fi
}

get_iface() {
    # Try to find the network interface
    local iface=$(ls /sys/class/net/usb* 2>/dev/null | head -n 1 | xargs basename 2>/dev/null)
    [ -z "$iface" ] && iface=$(ls /sys/class/net/wwan* 2>/dev/null | head -n 1 | xargs basename 2>/dev/null)
    if [ -z "$iface" ]; then
        # Fallback to general USB net devices
        iface=$(ls /sys/class/net/usb* 2>/dev/null | head -n 1 | xargs basename 2>/dev/null)
    else
        iface=$(basename "$iface")
    fi
    echo "$iface"
}

setup_iface() {
    local iface=$(get_iface)
    if [ -z "$iface" ]; then
        log "Error: Could not find network interface for modem"
        echo '{"error":"Network interface not found"}'
        return 1
    fi

    log "Configuring OpenWrt interface 'wan' on device $iface"
    if [ -z "$(uci get network.wan 2>/dev/null)" ]; then
        uci set network.wan=interface
    fi

    uci set network.wan.device="$iface"
    uci set network.wan.proto="dhcp"
    uci commit network
    /etc/init.d/network restart
    echo '{"status":"success","iface":"'$iface'"}'
}

#main
log "Starting A7908E APN configuration"

# Immediately set status to configuring before any AT commands are sent
model=$(cat /tmp/modem_model 2>/dev/null || echo "A7908E")
echo "{\"status\":\"configuring\",\"model\":\"$model\"}" > /tmp/lte_stats

disable_data_call

if [ -n "$slot" ]; then
    current_slot=$(get_cur_slot)
    if [ "$current_slot" != "$slot" ]; then
        set_sim_slot "$slot"
        log "Waiting for SIM switch and re-initialization..."
        sleep 10
    fi
fi

if [ -n "$service" ]; then
    set_mode_pref "$service"
    sleep 1
fi

CURRENT_NET=$(get_net)
if [ "$CURRENT_NET" != "1" ]; then
    set_ecm
    log "ECM mode set, waiting for modem to re-enumerate..."
    sleep 5
fi

if ! set_pdp_context "$apn"; then
    log "Critical Error: PDP Context setup failed. Exiting configuration."
    echo '{"error":"Failed to set PDP context"}'
    exit 1
fi

if ! set_data_call; then
    log "Warning: Data call activation returned error, attempting interface setup anyway"
fi

setup_iface

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

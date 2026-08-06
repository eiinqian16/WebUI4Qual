#!/bin/sh

echo "Content-type: text/plain"
echo "" 

read INPUT

MODEM_DEV="/dev/ttyUSB2"
LOG_FILE="/tmp/rm500u_config.log"

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

    touch /tmp/modem.lock
    exec 8>/tmp/modem.lock
    flock -x 8

    local resp
    resp=$(echo -e "${cmd}\r" | microcom -t $((timeout * 1000)) "$MODEM_DEV" 2>/dev/null | tr -d '\r')

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

case "$service" in
    NR5G-SA|NR5G-NSA|AUTO) : ;; # preserve literal token for AT+QNWPREFCFG="mode_pref",<token>
    *5G*) service="NR5G" ;;
    *lte*) service="LTE" ;;
esac

get_net() {
    local resp=$(at_cmd 'AT+QCFG="usbnet"')
    # Extract the numeric value
    echo "$resp" | grep -oE '\+QCFG: "usbnet",[0-9]+' | awk -F',' '{print $2}'
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
    local resp=$(at_cmd "AT+QUIMSLOT?")
    local val=$(echo "$resp" | grep "+QUIMSLOT:" | awk '{print $2}' | tr -dc '0-9')
    [ -n "$val" ] && echo "$val"
}

set_sim_slot() {
    local target_slot="$1"
    [ -z "$target_slot" ] && return 0

    log "Setting SIM slot to $target_slot (AT+QUIMSLOT=$target_slot)"
    local resp=$(at_cmd "AT+QUIMSLOT=$target_slot" 5)

    if echo "$resp" | grep -q "OK"; then
        return 0
    else
        return 1
    fi
}

set_mode_pref() {
    local pref="$1"
    [ -z "$pref" ] && return 0

    log "Setting mode preference to $pref"
    local resp=$(at_cmd "AT+QNWPREFCFG=\"mode_pref\",$pref" 3)
    if echo "$resp" | grep -q "OK"; then
        log "Mode preference set successfully"
        return 0
    else
        log "Error: Failed to set mode preference. Response: $resp"
        return 1
    fi
}

set_ecm() {
    log "Setting modem to ECM mode (usbnet,1)"
    at_cmd 'AT+QCFG="usbnet",1'
}

set_data_call() {
    log "Activating data call on context 1"
    local resp=$(at_cmd 'AT+QNETDEVCTL=3,1,1' 5)

    # Check for OK
    if echo "$resp" | grep -q "OK"; then
        log "Data call activated"
        return 0
    else
        log "Error: Data call activation failed. Response: $resp"
        return 1
    fi
}

disable_data_call() {
    log "Deactivating existing data calls"
    local resp=$(at_cmd 'AT+QNETDEVCTL=0,1,1' 3)

    if echo "$resp" | grep -q "OK"; then
        log "Data call deactivated"
        echo '{"disable_data_call":"OK"}'
        return 0;
    else 
        log "Warning: Data call deactivation failed. Response: $resp"
        echo '{"disable_data_call_error":"disable data call failed"}'
        echo "$resp"
        return 1
    fi
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
    # Try to find the specific Quectel network interface
    local iface=$(ls /sys/bus/usb/drivers/cdc_ether/*/net 2>/dev/null | head -n 1)
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
    uci set firewall.@zone[1].input=ACCEPT
    uci set firewall.@zone[1].forward=ACCEPT
    uci commit network
    uci commit firewall
    /etc/init.d/firewall restart
    /etc/init.d/network restart
    echo '{"status":"success","iface":"'$iface'"}'
}

#main
log "Starting RM500U APN configuration"

# Immediately set status to configuring before any AT commands are sent
model=$(cat /tmp/modem_model 2>/dev/null || echo "RM500U")
echo "{\"status\":\"configuring\",\"model\":\"$model\"}" > /tmp/lte_stats

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
fi

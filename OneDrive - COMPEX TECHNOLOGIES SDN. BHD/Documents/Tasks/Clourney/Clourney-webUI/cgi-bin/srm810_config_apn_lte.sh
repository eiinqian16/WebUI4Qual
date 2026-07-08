#!/bin/sh

echo "Content-type: text/plain"
echo "" 

read INPUT

MODEM_DEV="/dev/ttyUSB2"
LOG_FILE="/tmp/srm810_config.log"

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
    local LOCK_FILE="/tmp/modem.lock"

    touch "$LOCK_FILE"
    exec 8>"$LOCK_FILE"
    flock -x 8

    # Use microcom for reliable SRM810 communication
    local ms=$((timeout * 1000))
    resp=$(echo -e "$cmd\r" | microcom -t "$ms" "$MODEM_DEV" 2>/dev/null | tr -d '\r')

    # If response is empty, the modem might be busy or buffer is desynced
    if [ -z "$resp" ]; then
        sleep 1
        resp=$(echo -e "$cmd\r" | microcom -t "$ms" "$MODEM_DEV" 2>/dev/null | tr -d '\r')
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

check_internet() {
    local target_iface=$(get_iface)
    [ -n "$target_iface" ] && ping -I "$target_iface" -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 && return 0
    ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1
}

get_cur_slot() {
    local resp=$(at_cmd "AT^SIMSLOT?" 2)
    # SRM810: 1,1,0,0 is Slot 1; 0,0,1,1 is Slot 2
    if echo "$resp" | grep -q "0,0,1,1"; then
        echo 2
    else
        echo 1
    fi
}

set_sim_slot() {
    local target_slot="$1"
    [ -z "$target_slot" ] && return 0

    log "Setting SIM slot to $target_slot (AT^SIMSLOT=$target_slot)"
    local resp=$(at_cmd "AT^SIMSLOT=$target_slot" 5)

    if echo "$resp" | grep -q "OK"; then
        # Allow time for modem to re-initialize SIM stack
        sleep 5
        return 0
    else
        return 1
    fi
}

set_mode_pref() {
    local pref="$1"
    [ -z "$pref" ] && return 0

    local mode_val=""
    case "$pref" in
        "AUTO") mode_val="0403" ;;
        "NR5G") mode_val="04" ;;
        "LTE")   mode_val="03" ;;
        *)      mode_val="0403" ;; # Default to AUTO
    esac

    log "Setting mode preference to $pref (AT^SYSCFGEX=\"$mode_val\")"
    local resp=$(at_cmd "AT^SYSCFGEX=\"$mode_val\",2000004400000,0,2,1E2080800D5,0,1A0080800D5,3000,0" 3)
    if echo "$resp" | grep -q "OK"; then
        log "Mode preference set successfully"
        return 0
    else
        log "Error: Failed to set mode preference. Response: $resp"
        return 1
    fi
}

set_pdp_context() {
    local apn="$1"
    log "Configuring PDP Context 1 with APN: $apn"
    at_cmd "AT+CGPADDR=1" 3
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

get_iface() {
    local iface=$(ls -l /sys/class/net/ | grep -E "usb|cdc|qmi|mbim|rndis" | head -n 1 | awk '{print $9}')
    # Fallback to usb0 if grep finds nothing
    [ -z "$iface" ] && iface="usb0"
    echo "$iface"
}

setup_iface() {
    local iface=$(get_iface)
    if [ -z "$iface" ]; then
        log "Error: Could not find network interface for modem"
        echo '{"error":"Network interface not found"}'
        return 1
    fi

    local curr_dev=$(uci -q get network.wan.device)
    local curr_proto=$(uci -q get network.wan.proto)

    if [ "$force_config" -eq 0 ] && [ "$curr_dev" = "$iface" ] && [ "$curr_proto" = "dhcp" ]; then
        log "Network interface 'wan' already configured on $iface. Skipping setup."
        echo '{"status":"success","iface":"'$iface'","message":"Network unchanged"}'
        return 0
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
log "Starting SRM810 APN configuration"

# Check if current configuration already matches the request to avoid redundant restarts
if [ -f "/tmp/lte_stats" ]; then
    curr_op=$(jsonfilter -i /tmp/lte_stats -e '@.operator' 2>/dev/null)
    curr_rat=$(jsonfilter -i /tmp/lte_stats -e '@.rat' 2>/dev/null)
    curr_slot=$(jsonfilter -i /tmp/lte_stats -e '@.curSlot' 2>/dev/null)

    # Determine current service string based on numeric RAT from stats
    curr_svc="AUTO"
    [ "$curr_rat" = "7" ] && curr_svc="LTE"
    { [ "$curr_rat" = "11" ] || [ "$curr_rat" = "13" ]; } && curr_svc="NR5G"

    # Lookup what the APN should be for the current operator in the database
    curr_apn=$(jsonfilter -i "/www/webUI/db/apn-db.json" -e "@[\"$curr_op\"].APNs.LTE.apn" 2>/dev/null)
    [ -z "$curr_apn" ] && curr_apn=$(jsonfilter -i "/www/webUI/db/apn-db.json" -e "@[\"$curr_op\"].APNs.NR5G.apn" 2>/dev/null)

    if [ -n "$curr_op" ] && [ "$curr_apn" = "$apn" ] && [ "$curr_slot" = "$slot" ] && [ "$curr_svc" = "$service" ]; then
        log "Configuration matches current state (APN:$apn, Slot:$slot, Svc:$service). Skipping."
        echo '{"status":"success","message":"Config unchanged"}'
        exit 0
    fi
fi

# Immediately set status to configuring before any AT commands are sent
model=$(cat /tmp/modem_model 2>/dev/null || echo "SRM810")
[ "$model" = "5G Module" ] && model="SRM810"
echo "{\"status\":\"configuring\",\"model\":\"$model\"}" > /tmp/lte_stats
force_config=0

if [ -n "$slot" ]; then
    current_slot=$(get_cur_slot)
    if [ "$current_slot" != "$slot" ]; then
        set_sim_slot "$slot"
        force_config=1
        log "Waiting for SIM switch and re-initialization..."
        sleep 10
    fi
fi

if [ -n "$apn" ] && { [ "$force_config" -eq 1 ] || [ "$apn" != "$curr_apn" ]; }; then
    if ! set_pdp_context "$apn"; then
        log "Critical Error: PDP Context setup failed. Exiting configuration."
        echo '{"error":"Failed to set PDP context"}'
        exit 1
    fi
elif [ -n "$apn" ]; then
    log "APN $apn matches current operator configuration. Skipping PDP update."
fi

if [ -n "$service" ] && { [ "$force_config" -eq 1 ] || [ "$service" != "$curr_svc" ]; }; then
    set_mode_pref "$service"
    sleep 1
elif [ -n "$service" ]; then
    log "Service $service already active. Skipping mode preference update."
fi

setup_iface

# Post-configuration internet verification and recovery
log "Verifying internet connection..."
sleep 10

if ! check_internet; then
    log "No internet connection detected. Checking PDP status..."
fi

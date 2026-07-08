#!/bin/sh

echo "Content-type: text/plain"
echo ""

read INPUT
#INPUT="&proto=lte&apn=mycelcom4g&service=LTE&slot=0"

MODEM_DEV="/dev/ttyUSB2"
STATS_FILE="/tmp/lte_stats"
LOG_FILE="/tmp/manual_config.log"

if [ -z "$MODEM_DEV" ]; then
    echo '{"error": "No modem found"}'
    exit 1
fi

echo "Detected modem port: $MODEM_DEV"

log() { 
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1 $2" | tee -a "$LOG_FILE"
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

apn=$(extract_value "apn")
service=$(extract_value "service")
slot=$(extract_value "slot")

apn=${apn:-""}
service=${service:-""}
slot=${slot:-""}

echo "{\"status\":\"configuring\",\"ip\":\"\",\"curSlot\":\"$slot\"}" > /tmp/lte_stats

at_cmd() {
    local response=""
    # Open FD 3
    exec 3<> "$MODEM_DEV"
    # Send command
    printf "%s\r\n" "$1" >&3
    # Read response
    response=$(timeout 2 cat <&3 2>/dev/null | tr -d '\r')
    # Close FD 3
    exec 3>&-
    echo "$response"
}

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
        if [ $retry -lt $max_retries ]; then
            log "WARN" "AT command retry $retry/$max_retries: $cmd"
            sleep 2
        fi
    done
    
    log "ERROR" "AT command failed after $max_retries attempts: $cmd"
    return 1
}

get_net() {
    resp=$(at_cmd 'AT+QCFG="usbnet"')
    usbnet=$(echo "$resp" | grep "+QCFG:" | awk -F',' '{print $NF}' | tr -d '[:space:]')
    echo "$usbnet"
}

set_ecm() {
    exec 3<> "$MODEM_DEV"
    at_cmd 'AT+QCFG="usbnet",1'
}

set_data_call() {
    exec 3<> "$MODEM_DEV"
    echo -e 'AT+QNETDEVCTL=3,1,1\r' >&3
    resp=$(timeout 1 cat <&3 2>/dev/null || true)
    exec 3>&-
    # Check for OK
    if echo "$resp" | grep -q "OK"; then
        echo '{"set_data_call_result":"OK"}'
        return 0
    else
        echo '{"set_data_call_result_error":"data call failed"}'
        echo "$resp"
        return 1
    fi
}

set_mpdn_call() {
    local resp=$(at_cmd 'AT+QMAP="mpdn_rule",0,1,0,3,1,"FF:FF:FF:FF:FF:FF"')
    if echo "$resp" | grep -q "OK"; then
        echo '{"result":"OK"}' && return 0
    fi
    return 1
}

disable_data_call() {
    exec 3<> "$MODEM_DEV"
    echo -e 'AT+QNETDEVCTL=0,1,1\r' >&3
    resp=$(timeout 1 cat <&3 2>/dev/null || true)
    exec 3>&-
    if echo "$resp" | grep -q "OK"; then
        echo '{"disable_data_call":"OK"}'
        return 0;
    else 
        echo '{"disable_data_call_error":"disable data call failed"}'
        echo "$resp"
        return 1
    fi
}

disable_mpdn_call() {
    exec 3<> "$MODEM_DEV"
    echo -e 'AT+QMAP="mpdn_rule",0' >&3
    resp=$(timeout 5 cat <&3 2>/dev/null || true)
    exec 3>&-
    if echo "$resp" | grep -q "OK"; then
        echo '{"disable_mpdn_call_result":"OK"}'
        return 0
    else
        echo '{"disable_mpdn_call_result":"disable mpdn call failed"}'
        echo "$resp"
        return 1
    fi
}

set_pdp_context() {
    local apn="$1"
    exec 3<> "$MODEM_DEV"
    echo -e "AT+CGDCONT=1,\"IPV4V6\",\"${apn}\"\r" >&3 
    sleep 1
    resp=$(timeout 1 cat <&3 2>/dev/null | tr -d '\r' || true)
    exec 3>&-
    if echo "$resp" | grep -q "OK"; then
        echo '{"set_pdp_context_result":"OK"}'
        return 0
    else
        echo '{"set_pdp_context_error":"PDP config failed"}'
        echo "$resp"
        return 1
    fi
}

set_slot() {
    local slot=$1
    local resp=$(at_cmd "AT+QUIMSLOT=$slot")
    if echo "$resp" | grep -q "OK"; then
        echo '{"sim set result":"OK"}' && return 0
    fi
    return 1
}

set_mode_pref() {
    local service="$1"
    local resp=$(at_cmd "AT+QNWPREFCFG=\"mode_pref\",${service}")

    if echo "$resp" | grep -q "OK"; then
        echo '{"set_mode_pref_result":"OK"}'
        return 0
    else
        echo '{"set_mode_pref_error":"set mode pref failed"}'
        echo "$resp"
        return 1
    fi
}

enable_qmapwac() {
    log "INFO" "Enabling QMAP WAC..."
    local resp=$(at_cmd_retry "AT+QMAPWAC=1" 3)
    
    if echo "$resp" | grep -q "OK"; then
        log "INFO" "QMAP WAC enabled successfully"
        return 0
    fi
    log "WARN" "QMAP WAC enable returned: $resp"
    return 0  # Don't fail on this
}

restart_modem() {
    log "INFO" "Restarting modem..."
    at_cmd 'AT+CFUN=1,1' > /dev/null
    
    # Give the kernel time to actually remove the device node
    sleep 5 
    
    local wait_count=0
    while [ ! -c "$MODEM_DEV" ] && [ $wait_count -lt 60 ]; do
        sleep 2
        wait_count=$((wait_count + 2))
        log "DEBUG" "Waiting for $MODEM_DEV to reappear... ($wait_count/60)"
    done

    if [ -c "$MODEM_DEV" ]; then
        log "INFO" "Modem device node back online. Waiting for boot..."
        sleep 10 # Essential: the node exists but the internal AT parser isn't ready yet
        return 0
    fi
    return 1
}

check_iccid() {
    local slot=$1
    local resp=$(at_cmd "AT+ICCID?")
    local iccid=$(echo "$resp" | grep "+ICCID:" | tr -dc '0-9')

    if [ -n "$iccid" ]; then
        if [ "$slot" = "1" ]; then
            echo "{\"iccid\":\"$iccid\"}" > "/tmp/modem_iccid_1"
        elif [ "$slot" = "2" ]; then
            echo "{\"iccid\":\"$iccid\"}" > "/tmp/modem_iccid_2"
        fi
    fi
}

check_modem_ready() {
    local max_attempts=10
    local attempt=0
    
    log "INFO" "Checking modem readiness..."
    
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        
        resp=$(at_cmd "AT" 2)
        
        if echo "$resp" | grep -q "OK"; then
            log "INFO" "Modem is ready"
            return 0
        fi
        
        log "WARN" "Modem not ready, attempt $attempt/$max_attempts"
        sleep 3
    done
    
    log "ERROR" "Modem failed to respond after $max_attempts attempts"
    return 1
}

check_connection() {
    local expected_plmn="$1"
    local max_attempts=10
    local attempt=0
    
    echo "Checking connection to PLMN: $expected_plmn" >&2
    
    # Wait for registration with retry logic
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        
        exec 3<> "$MODEM_DEV"
        # Set format to numeric (2)
        echo -e "AT+COPS=3,2\r" >&3
        sleep 1
        # Clear the buffer
        timeout 1 cat <&3 > /dev/null 2>&1 || true
        
        # Now query the operator
        echo -e "AT+COPS?\r" >&3
        sleep 1
        resp=$(timeout 2 cat <&3 2>/dev/null | tr -d '\r\n' || true)
        exec 3>&-
        
        res_plmn=$(echo "$resp" | awk -F'"' '{print $2}')
        
        echo "Attempt $attempt: Expected=$expected_plmn, Got=$res_plmn" >&2
        
        if [ -n "$res_plmn" ] && [ "$res_plmn" = "$expected_plmn" ]; then
            echo '{"connection_status":"success","plmn":"'"$res_plmn"'"}'
            return 0
        fi
        
        # Wait before retry
        sleep 2
    done
    
    # Failed after all attempts
    echo '{"connection_status":"failed","expected":"'"$expected_plmn"'","got":"'"$res_plmn"'"}'
    return 1
}

get_iface() {
    for i in /sys/class/net/*; do
        dev=$(basename "$i")
        path=$(readlink -f "$i/device" 2>/dev/null)
        if echo "$path" | grep -qE "usb|cdc|qmi|mbim|rndis"; then
            echo "$dev"
            return
        fi
    done
}

setup_iface() {
    iface=$(get_iface)
    if [ -z "$iface" ]; then
        echo "No network interface found"
        return 1
    fi
    
    if [ -z "$(uci get network.wan 2>/dev/null)" ]; then
        uci set network.wan=interface
    fi
    uci set network.wan.device="$iface"
    uci set network.wan.proto="dhcp"
    uci commit network
    /etc/init.d/network restart
}

MODEM_DEV=/dev/ttyUSB2

if [ ! -c "$MODEM_DEV" ]; then
    echo "No modem found at $MODEM_DEV, exiting ..."
    exit 1
fi

set_slot "$slot"
sleep 5
wait_count=0
while [ ! -c "$MODEM_DEV" ] && [ $wait_count -lt 40 ]; do
    sleep 2
    wait_count=$((wait_count + 2))
done

if [ "$(get_net)" = "1" ]; then
    echo "ECM mode already enabled"
else
    echo "Setting ECM mode"
    set_ecm
    sleep 5
fi

set_mode_pref "$service"

set_pdp_context "$apn"
sleep 2

check_iccid "$slot"
sleep 2

enable_qmapwac

if ! restart_modem; then
    log "ERROR" "Modem restart failed"
    exit 1
fi

# Setup network interface
setup_iface
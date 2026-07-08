#!/bin/sh

echo "Content-Type: application/json"
echo ""

STATUS_FILE="/tmp/lte_stats"
STATS_LINK="/www/webUI/modem_stats"
MODEM_DEV="/dev/ttyUSB2"
ICCID_FILE_1="/tmp/modem_iccid_1"
ICCID_FILE_2="/tmp/modem_iccid_2"
LOG_FILE="/tmp/lte_stats.log"
LED_GREEN="green:status"
LED_RED="red:status"

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

log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE" >&2
}

check_led() {
    local led_path="/sys/class/leds/$1/brightness"
    if [ -f "$led_path" ] && [ "$(cat "$led_path")" -gt 0 ]; then
        return 0
    fi
    return 1
}

validate_modem() {
    if [ ! -c "$MODEM_DEV" ]; then
        log "ERROR" "Modem device not found at $MODEM_DEV"
        
        # Try to find alternative modem devices
        log "INFO" "Searching for alternative modem devices..."
        for dev in /dev/ttyUSB* /dev/ttyACM* /dev/cdc-wdm*; do
            if [ -c "$dev" ]; then
                log "INFO" "Found potential modem device: $dev"
            fi
        done
        return 1
    fi
    
    # Check if device is readable/writable
    if [ ! -r "$MODEM_DEV" ] || [ ! -w "$MODEM_DEV" ]; then
        log "ERROR" "Insufficient permissions for $MODEM_DEV"
        return 1
    fi
    
    log "INFO" "Modem device validated: $MODEM_DEV"
    return 0
}

acquire_lock() {
    local timeout=30
    local elapsed=0
    
    # Try to acquire lock with timeout
    while [ $elapsed -lt $timeout ]; do
        if flock -n 200 2>/dev/null; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    
    log "ERROR" "Failed to acquire lock after ${timeout}s"
    return 1
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

# Restart modem
restart_modem() {
    log "INFO" "Restarting modem (AT+CFUN=1,1)..."
    
    at_cmd_retry 'AT+CFUN=1,1' 3
    
    log "INFO" "Waiting for modem to restart..."
    sleep 10
    
    local wait_count=0
    local max_wait=150
    
    # Wait for device to reappear and be ready
    while [ $wait_count -lt $max_wait ]; do
        if [ -c "$MODEM_DEV" ]; then
            sleep 3
            # Try to communicate
            if at_cmd "AT" 2 | grep -q "OK"; then
                log "INFO" "Modem has restarted and is responsive"
                return 0
            fi
        fi
        sleep 2
        wait_count=$((wait_count + 2))
        
        if [ $((wait_count % 10)) -eq 0 ]; then
            log "DEBUG" "Waiting for modem... ($wait_count/$max_wait seconds)"
        fi
    done
    
    log "ERROR" "Modem did not become responsive after restart"
    return 1
}

at_cmd() {
    local cmd="$1"
    local timeout="${2:-2}"
    local response=""

    # Use lock to prevent collision with configuration scripts
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

get_iccid() {
    local slot=$1
    local resp=$(at_cmd "AT+CICCID")
    echo "$resp" | grep "+ICCID:" | awk '{print $2}' | tr -d '\r\n '
}

check_internet() {
    local target_iface=$(uci -q get network.wan.device)
    [ -z "$target_iface" ] && target_iface="usb0"
    
    ping -I "$target_iface" -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1
}

# Set status to configuring before data is updated to prevent stale data usage
model=$(cat /tmp/modem_model 2>/dev/null || echo "A7908E")
echo "{\"status\":\"configuring\",\"model\":\"$model\"}" > "$STATUS_FILE"

serving=$(at_cmd 'AT+CPSI?' 3)

# 1. Parse Operator and RAT (Derive from +CPSI fields 3 and 1)
plmn_raw=$(echo "$serving" | grep '^+CPSI:' | awk -F',' '{print $3}')
mcc=$(echo "$plmn_raw" | cut -d'-' -f1 | tr -dc '0-9')
mnc=$(echo "$plmn_raw" | cut -d'-' -f2 | tr -dc '0-9')
operator="${mcc}${mnc}"
[ -z "$mcc" ] && operator="No operator detected"

rat_mode=$(echo "$serving" | grep '^+CPSI:' | awk -F',' '{print $1}' | sed 's/^+CPSI: //')
case "$rat_mode" in
    "LTE") rat="7" ;;
    "NR5G"*) rat="11" ;;
    *) rat="No band found" ;;
esac

# 2. Parse Signal Metrics with Conversion (ASR Chipset Math)
band=$(echo "$serving" | grep '^+CPSI:' | awk -F',' '{print $7}' | sed 's/.*BAND//' | tr -dc '0-9')
val_rsrq=$(echo "$serving" | grep '^+CPSI:' | awk -F',' '{print $11}' | tr -dc '0-9')
val_rsrp=$(echo "$serving" | grep '^+CPSI:' | awk -F',' '{print $12}' | tr -dc '0-9')
val_snr=$(echo "$serving" | grep '^+CPSI:' | awk -F',' '{print $14}' | tr -dc '0-9')

# Convert raw indices to standard units
[ -n "$val_rsrp" ] && rsrp=$((val_rsrp - 140))
[ -n "$val_rsrq" ] && rsrq=$(awk "BEGIN {print ($val_rsrq - 40) / 2}")
[ -n "$val_snr" ] && snr=$((val_snr - 20))

# get interface of modem
iface=$(uci -q get network.wan.device)
if [ -z "$iface" ] || [ "$iface" = "br-lan" ]; then
    bus=$(grep -m1 "Asrmicro" -B4 /sys/kernel/debug/usb/devices | grep -m1 "Bus=" | sed -nE 's/.*Bus=0*([0-9]+).*/\1/p')
    lev=$(grep -m1 "Asrmicro" -B4 /sys/kernel/debug/usb/devices | grep -m1 "Lev=" | sed -nE 's/.*Lev=0*([0-9]+).*/\1/p')
    prnt=$(grep -m1 "Asrmicro" -B4 /sys/kernel/debug/usb/devices | grep -m1 "Prnt=" | sed -nE 's/.*Prnt=0*([0-9]+).*/\1/p')
    port=$(grep -A20 "Asrmicro" /sys/kernel/debug/usb/devices | grep -E "Driver=(cdc_ether|qmi_wwan|cdc_mbim)" | head -n 1 | sed 's/.*If#=\s*\([0-9]*\).*/\1/')
    driver=$(awk '/Asrmicro/{flag=1} flag; /^$/{flag=0}' /sys/kernel/debug/usb/devices \
        | grep "Driver=" | grep -E "cdc|qmi" | grep -v "option" -m1 \
        | sed -nE 's/.*Driver=([a-zA-Z0-9_+-]+).*/\1/p')
    id="${bus}-${lev}:${prnt}.${port}"
    iface=$(ls "/sys/bus/usb/drivers/$driver/$id/net" 2>/dev/null | head -n 1)
fi

[ -z "$iface" ] && [ -d /sys/class/net/usb0 ] && iface="usb0"
[ -z "$iface" ] && [ -d /sys/class/net/wwan0 ] && iface="wwan0"

if [ -n "$iface" ]; then
    if [ "$(uci -q get network.wan.device)" == "$iface" ]; then
        proto=$(uci -q get network.wan.proto)
    fi

    #get network info of interface
    ip=$(ifconfig "$iface" 2>/dev/null | grep -i "inet addr" | awk -F ':' '{print $2}' | awk '{print $1}' | head -n 1)
    subnet=$(ifconfig "$iface" 2>/dev/null | grep -i "mask" | awk -F ':' '{print $4}' | head -n 1)
    bcast=$(ifconfig "$iface" 2>/dev/null | grep -i "bcast" | awk -F ':' '{print $3}' | awk '{print $1}' | head -n 1)
    hwaddr=$(ifconfig "$iface" 2>/dev/null | grep -i "hwaddr" | awk '{print $5}' | head -n 1)
    routeIf=$(ip route | grep -i "default via" | awk '{print $5}' | head -n 1)
    if [ "$routeIf" = "$iface" ]; then
        gateway=$(ip route | grep -i "default via" | awk '{print $3}' | head -n 1)
    fi
fi

sim1_iccid=$(jsonfilter -i "$ICCID_FILE_1" -e '@.iccid' 2>/dev/null || echo "No SIM detected")
sim2_iccid=$(jsonfilter -i "$ICCID_FILE_2" -e '@.iccid' 2>/dev/null || echo "No SIM detected")

# Simcom A7908E Slot Detection via GPIO 22
if [ -d "/sys/class/gpio/gpio22" ]; then
    gpio_val=$(cat /sys/class/gpio/gpio22/value 2>/dev/null)
    [ "$gpio_val" = "0" ] && cur_slot=1 || cur_slot=2
fi

# Determine ready status only after all data has been updated and verified
if check_internet; then
    status="ready"
else
    status="configuring"
fi

model=$(cat /sys/kernel/debug/usb/devices | awk '/Vendor=1e0e/ {flag=1} flag && /Product=/ {print $0; flag=0}' | awk -F'Product=' '{print $2}' | head -n 1 | tr -d '\r\n ')
case "$model" in ""|"Asrmicro") model="A7908E" ;; esac

#echo "Bus: $bus"
#echo "Lev: $lev"
#echo "Prnt: $prnt"
#echo "Port: $port"
#echo "Driver: $driver"
#echo "Iface: $iface"
#echo "rat: $rat"
#echo "$proto"
#echo "IP: $ip"

json_output=""
[ -n "$model" ]      && json_output="${json_output},\"model\":\"${model}\""
[ -n "$status" ]     && json_output="${json_output},\"status\":\"${status}\""
[ -n "$operator" ]   && json_output="${json_output},\"operator\":\"${operator}\""
[ -n "$rat" ]        && json_output="${json_output},\"rat\":\"${rat}\""
[ -n "$iface" ]      && json_output="${json_output},\"iface\":\"${iface}\""
[ -n "$ip" ]         && json_output="${json_output},\"ip\":\"${ip}\""
[ -n "$proto" ]      && json_output="${json_output},\"proto\":\"${proto}\""
[ -n "$subnet" ]     && json_output="${json_output},\"subnet\":\"${subnet}\""
[ -n "$bcast" ]      && json_output="${json_output},\"bcast\":\"${bcast}\""
[ -n "$hwaddr" ]     && json_output="${json_output},\"hwaddr\":\"${hwaddr}\""
[ -n "$gateway" ]    && json_output="${json_output},\"gateway\":\"${gateway}\""
[ -n "$mcc" ]        && json_output="${json_output},\"mcc\":\"${mcc}\""
[ -n "$mnc" ]        && json_output="${json_output},\"mnc\":\"${mnc}\""
[ -n "$band" ]       && json_output="${json_output},\"band\":\"${band}\""
[ -n "$rsrp" ]       && json_output="${json_output},\"rsrp\":\"${rsrp}\""
[ -n "$rsrq" ]       && json_output="${json_output},\"rsrq\":\"${rsrq}\""
[ -n "$snr" ]        && json_output="${json_output},\"snr\":\"${snr}\""
[ -n "$sim1_iccid" ] && json_output="${json_output},\"sim1iccid\":\"${sim1_iccid}\""
[ -n "$sim2_iccid" ] && json_output="${json_output},\"sim2iccid\":\"${sim2_iccid}\""
[ -n "$cur_slot" ]   && json_output="${json_output},\"curSlot\":\"${cur_slot}\""

json_output="{$(echo "$json_output" | sed 's/^[[:space:],]*//')}"

echo "$json_output" > "$STATUS_FILE"
echo "$json_output"

if [ ! -L "$STATS_LINK" ]; then
    ln -s "$STATUS_FILE" "$STATS_LINK"
fi

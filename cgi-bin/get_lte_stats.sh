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

get_iccid() {
    local slot=$1
    local resp=$(at_cmd "AT+ICCID")
    echo "$resp" | grep "+ICCID:" | awk '{print $2}' | tr -d '\r\n '
}

check_internet() {
    if ping -I usb0 -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

at_cmd "AT+COPS=3,2" > /dev/null
resp=$(at_cmd "AT+COPS?")

# Wait for response
sleep 1

# Extract operator name 
operator=$(echo "$resp" | grep "+COPS:" | head -n 1 | awk -F',' '{gsub(/"/,"",$3); print $3}' | tr -d '\r\n ')

if [ -z "$operator" ]; then
    operator="No operator detected"
fi

# Extract RAT 
rat=$(echo "$resp" | grep "+COPS:" | head -n 1 | awk -F',' '{print $4}' | tr -d '\r\n ')

if [ -z "$rat" ]; then
    rat="No band found"
fi

serving=$(echo -e 'AT+QENG="servingcell"\r' | microcom -t 3000 "$MODEM_DEV")

clean_serving=$(echo "$serving" | tr -d '"' | sed 's/^+QENG: //')

mcc=$(echo "$clean_serving" | awk -F ',' '/servingcell/ {print $5}' | tr -dc '0-9')
mnc=$(echo "$clean_serving" | awk -F ',' '/servingcell/ {print $6}' | tr -dc '0-9')

if [ "$rat" == "7" ]; then 
    band=$(echo "$clean_serving" | awk -F ',' '/servingcell/ {print $10}' | tr -dc '0-9-')
    rsrp=$(echo "$clean_serving" | awk -F ',' '/servingcell/ {print $14}' | tr -dc '0-9-')
    rsrq=$(echo "$clean_serving" | awk -F ',' '/servingcell/ {print $15}' | tr -dc '0-9-')
    snr=$(echo "$clean_serving" | awk -F ',' '/servingcell/ {print $17}' | tr -dc '0-9.-')

elif [ "$rat" == "11" ]; then
    band=$(echo "$clean_serving" | awk -F ',' '/servingcell/ {print $11}' | tr -dc '0-9-')
    rsrp=$(echo "$clean_serving" | awk -F ',' '/servingcell/ {print $13}' | tr -dc '0-9-')
    rsrq=$(echo "$clean_serving" | awk -F ',' '/servingcell/ {print $14}' | tr -dc '0-9-')
    snr=$(echo "$clean_serving" | awk -F ',' '/servingcell/ {print $15}' | tr -dc '0-9.-')
fi


# get interface of modem
modem_block=$(awk '/Quectel/{flag=1} flag; /^$/{flag=0}' /sys/kernel/debug/usb/devices)
bus=$(grep -m1 "Quectel" -B4 /sys/kernel/debug/usb/devices | grep -m1 "Bus=" | sed -nE 's/.*Bus=0*([0-9]+).*/\1/p')
lev=$(grep -m1 "Quectel" -B4 /sys/kernel/debug/usb/devices | grep -m1 "Lev=" | sed -nE 's/.*Lev=0*([0-9]+).*/\1/p')
prnt=$(grep -m1 "Quectel" -B4 /sys/kernel/debug/usb/devices | grep -m1 "Prnt=" | sed -nE 's/.*Prnt=0*([0-9]+).*/\1/p')
port=$(grep -A20 "Quectel" /sys/kernel/debug/usb/devices | grep "Driver=cdc_ether" | head -n 1 | sed 's/.*If#=\s*\([0-9]*\).*/\1/')
driver=$(awk '/Quectel/{flag=1} flag; /^$/{flag=0}' /sys/kernel/debug/usb/devices \
    | grep "Driver=" | grep "cdc" | grep -v "option" -m1 \
    | sed -nE 's/.*Driver=([a-zA-Z0-9_+-]+).*/\1/p')
id="${bus}-${lev}:${prnt}.${port}"
iface=$(ls /sys/bus/usb/drivers/$driver/$id/net 2>/dev/null)
if [ $(uci get network.wan.device) == "$iface" ]; then
    proto=$(uci get network.wan.proto)
fi

#get network info of interface
ip=$(ifconfig $iface | grep -i "inet addr" | awk -F ':' '{print $2}' | awk -F ' ' '{print $1}')
subnet=$(ifconfig $iface | grep -i "mask" | awk -F ':' '{print $4}')
bcast=$(ifconfig $iface | grep -i "bcast" | awk -F ':' '{print $3}' | awk -F ' ' '{print $1}')
hwaddr=$(ifconfig $iface | grep -i "hwaddr" | awk -F ' ' '{print $5}')
routeIf=$(ip route | grep -i "default via" | awk '{print 5}')
if [ "$routeIf" = "$iface" ]; then
    gateway=$(ip route | grep -i "default via" | awk '{print $3}')
fi

sim1_iccid="No SIM detected"
sim2_iccid="No SIM detected"

if [ -f "$ICCID_FILE_1" ]; then
    val=$(jsonfilter -i "$ICCID_FILE_1" -e '@.iccid')
    [ -n "$val" ] && [ "$val" != "NA" ] && sim1_iccid="$val"
fi

if [ -f "$ICCID_FILE_2" ]; then
    val=$(jsonfilter -i "$ICCID_FILE_2" -e '@.iccid')
    [ -n "$val" ] && [ "$val" != "NA" ] && sim2_iccid="$val"
fi

slot_resp=$(at_cmd "AT+QUIMSLOT?")
cur_slot=$(echo "$slot_resp" | grep "+QUIMSLOT:" | awk '{print $2}' | tr -d '\r\n ')

if check_internet; then
    status="ready"
else
    status="configuring"
fi

USB_INFO=$(cat /sys/kernel/debug/usb/devices | grep -A 5 "Vendor=2c7c ProdID=0316")

model=$(echo "$USB_INFO" | grep "Product=" | awk -F'Product=' '{print $2}' | tr -d '\r\n ')

#echo "Bus: $bus"
#echo "Lev: $lev"
#echo "Prnt: $prnt"
#echo "Port: $port"
#echo "Driver: $driver"
#echo "Iface: $iface"
#echo "rat: $rat"
#echo "$proto"
#echo "IP: $ip"

json_output="{"
[ -n "$model" ]            && json_output="${json_output}\"model\":\"${model}\""
[ -n "$status" ]      && json_output="${json_output},\"status\":\"${status}\""
[ -n "$operator" ]      && json_output="${json_output},\"operator\":\"${operator}\""
[ -n "$rat" ]           && json_output="${json_output},\"rat\":\"${rat}\""
[ -n "$iface" ]         && json_output="${json_output},\"iface\":\"${iface}\""
[ -n "$ip" ]            && json_output="${json_output},\"ip\":\"${ip}\""
[ -n "$proto" ]         && json_output="${json_output},\"proto\":\"${proto}\""
[ -n "$subnet" ]        && json_output="${json_output},\"subnet\":\"${subnet}\""
[ -n "$bcast" ]         && json_output="${json_output},\"bcast\":\"${bcast}\""
[ -n "$hwaddr" ]        && json_output="${json_output},\"hwaddr\":\"${hwaddr}\""
[ -n "$gateway" ]       && json_output="${json_output},\"gateway\":\"${gateway}\""
[ -n "$mcc" ]            && json_output="${json_output},\"mcc\":\"${mcc}\""
[ -n "$mnc" ]            && json_output="${json_output},\"mnc\":\"${mnc}\""
[ -n "$band" ]            && json_output="${json_output},\"band\":\"${band}\""
[ -n "$rsrp" ]            && json_output="${json_output},\"rsrp\":\"${rsrp}\""
[ -n "$rsrq" ]            && json_output="${json_output},\"rsrq\":\"${rsrq}\""
[ -n "$snr" ]            && json_output="${json_output},\"snr\":\"${snr}\""
[ -n "$sim1_iccid" ]            && json_output="${json_output},\"sim1iccid\":\"${sim1_iccid}\""
[ -n "$sim2_iccid" ]            && json_output="${json_output},\"sim2iccid\":\"${sim2_iccid}\""
[ -n "$cur_slot" ]            && json_output="${json_output},\"curSlot\":\"${cur_slot}\""
json_output="${json_output}}"

echo "$json_output" > "$STATUS_FILE"
if [ ! -L "$STATS_LINK" ]; then
    ln -s "$STATUS_FILE" "$STATS_LINK"
fi


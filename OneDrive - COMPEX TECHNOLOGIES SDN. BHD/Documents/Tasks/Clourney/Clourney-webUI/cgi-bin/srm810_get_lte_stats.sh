#!/bin/sh

echo "Content-Type: application/json"
echo ""

STATUS_FILE="/tmp/lte_stats"
STATS_LINK="/www/webUI/modem_stats"
MODEM_DEV="/dev/ttyUSB2"
ICCID_FILE_1="/tmp/modem_iccid_1"
ICCID_FILE_2="/tmp/modem_iccid_2"
LOG_FILE="/tmp/lte_stats.log"
LOCK_FILE="/tmp/modem.lock"
LED_GREEN="green:status"
LED_RED="red:status"

log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE" >&2
}

# Improved AT command with proper serial handling
at_cmd() {
    local cmd="$1"
    local timeout="${2:-3}"
    local response=""
    
    [ -c "$MODEM_DEV" ] || {
        log "ERROR" "Device $MODEM_DEV not found"
        return 1
    }

    # Ensure lock file exists
    touch "$LOCK_FILE"
    exec 8>"$LOCK_FILE"
    
    if flock -x 8; then
        # Small delay to ensure device is ready
        sleep 1
        
        # Convert timeout to milliseconds for microcom
        local ms=$((timeout * 1000))
        
        # Send command through microcom with timeout
        # CRITICAL FIX: Remove both \r AND \n from response, and strip leading/trailing whitespace
        response=$(echo -e "$cmd\r" | microcom -t "$ms" "$MODEM_DEV" 2>/dev/null | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        flock -u 8
    else
        log "WARN" "Failed to acquire lock for: $cmd"
    fi

    exec 8>&-
    
    if [ -n "$response" ]; then
        echo "$response"
        return 0
    fi
    
    return 1
}

at_cmd_retry() {
    local cmd="$1"
    local timeout="${2:-3}"
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

check_modem_ready() {
    local max_attempts=5
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
        sleep 2
    done
    
    log "ERROR" "Modem failed to respond after $max_attempts attempts"
    return 1
}

check_internet() {
    local target_iface="$1"
    [ -z "$target_iface" ] && target_iface=$(uci -q get network.wan.device)
    [ -z "$target_iface" ] && target_iface="usb0"

    # 1. Primary check: Does the interface have a valid IP assigned?
    ifconfig "$target_iface" 2>/dev/null | grep -q "inet addr:" && return 0

    # 2. Secondary check: Try to ping with a longer timeout
    ping -I "$target_iface" -c 1 -W 5 8.8.8.8 >/dev/null 2>&1
}

get_iccid() {
    local slot=$1
    local resp=$(at_cmd "AT+ICCID" 2)
    echo "$resp" | grep -i "+ICCID:" | sed 's/.*+ICCID:[[:space:]]*//' | tr -d '[:space:]'
}

# Helper function to extract and clean numeric values
extract_numeric_field() {
    local data="$1"
    local field="$2"
    # Extract field value, remove all whitespace and newlines, keep only digits and minus sign
    echo "$data" | grep -oE "${field}:[[:space:]]*-?[0-9]+" | sed "s/${field}:[[:space:]]*//" | tr -d ' \n\r'
}

# Helper function to extract string values
extract_string_field() {
    local data="$1"
    local field="$2"
    # Extract field value, remove all whitespace and newlines
    echo "$data" | grep -oE "${field}:[[:space:]]*[A-Z0-9-]+" | sed "s/${field}:[[:space:]]*//" | tr -d ' \n\r'
}

# Parse serving cell info with better error handling
parse_serving_cell_info() {
    local info="$1"
    
    if [ -z "$info" ]; then
        log "WARN" "Empty serving cell info received"
        echo ""
        return 1
    fi
    
    # First pass: remove all newlines and excess whitespace globally
    local cleaned=$(echo "$info" | tr '\n' ' ' | tr '\r' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Extract each field with defensive parsing
    local curr_mode=$(extract_string_field "$cleaned" "CURR_MODE")
    local mcc=$(extract_numeric_field "$cleaned" "MCC")
    local mnc=$(extract_numeric_field "$cleaned" "MNC")
    local band=$(extract_numeric_field "$cleaned" "BAND")
    local rsrq=$(extract_numeric_field "$cleaned" "RSRQ")
    local rsrp=$(extract_numeric_field "$cleaned" "RSRP")
    local sinr=$(extract_numeric_field "$cleaned" "SINR")
    
    # Validate extracted values are reasonable
    # MCC should be exactly 3 digits
    if [ -n "$mcc" ] && ! echo "$mcc" | grep -qE '^[0-9]{3}$'; then
        log "WARN" "Invalid MCC format: '$mcc', discarding"
        mcc=""
    fi
    
    # MNC should be 2-3 digits
    if [ -n "$mnc" ] && ! echo "$mnc" | grep -qE '^[0-9]{2,3}$'; then
        log "WARN" "Invalid MNC format: '$mnc', discarding"
        mnc=""
    fi
    
    # RSRP and RSRQ should be negative values (or small positive)
    if [ -n "$rsrp" ] && ! echo "$rsrp" | grep -qE '^-?[0-9]{1,3}$'; then
        log "WARN" "Invalid RSRP format: '$rsrp', discarding"
        rsrp=""
    fi
    
    if [ -n "$rsrq" ] && ! echo "$rsrq" | grep -qE '^-?[0-9]{1,3}$'; then
        log "WARN" "Invalid RSRQ format: '$rsrq', discarding"
        rsrq=""
    fi
    
    # Echo all parsed values as colon-separated string
    echo "${curr_mode}:${mcc}:${mnc}:${band}:${rsrq}:${rsrp}:${sinr}"
}

# Helper to safely extract JSON field value
extract_json_value() {
    local json_file="$1"
    local field="$2"
    local default="${3:-No SIM detected}"
    
    if [ -f "$json_file" ]; then
        local value=$(jsonfilter -i "$json_file" -e "@.${field}" 2>/dev/null)
        if [ -n "$value" ] && [ "$value" != "null" ]; then
            echo "$value"
            return 0
        fi
    fi
    
    echo "$default"
    return 1
}

# Helper to safely add JSON field (only if value is non-empty and valid)
add_json_field() {
    local json_str="$1"
    local key="$2"
    local value="$3"
    
    # Skip empty values
    if [ -z "$value" ]; then
        echo "$json_str"
        return 0
    fi
    
    # Escape special characters in value for JSON
    value=$(echo "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
    
    # Add field
    if [ -z "$json_str" ]; then
        echo "\"${key}\":\"${value}\""
    else
        echo "${json_str},\"${key}\":\"${value}\""
    fi
}

# Set status to configuring before data is updated to prevent stale data usage
echo '{"status":"configuring"}' > "$STATUS_FILE"

# Validate modem is present and ready
if ! validate_modem; then
    log "ERROR" "Modem validation failed"
    echo '{"status":"error","message":"Modem device not found"}' > "$STATUS_FILE"
    cat "$STATUS_FILE"
    exit 1
fi

# Check modem is responsive
if ! check_modem_ready; then
    log "WARN" "Modem not responsive, continuing with limited data"
fi

# Get signal metrics and network info from AT+SGCELLINFOEX?
log "INFO" "Retrieving serving cell information..."
serving_cell_info=$(at_cmd_retry 'AT+SGCELLINFOEX?' 4)

if [ -n "$serving_cell_info" ]; then
    log "DEBUG" "Got serving cell response, parsing..."
    parsed=$(parse_serving_cell_info "$serving_cell_info")
    
    curr_mode=$(echo "$parsed" | cut -d: -f1)
    mcc=$(echo "$parsed" | cut -d: -f2)
    mnc=$(echo "$parsed" | cut -d: -f3)
    band=$(echo "$parsed" | cut -d: -f4)
    rsrq=$(echo "$parsed" | cut -d: -f5)
    rsrp=$(echo "$parsed" | cut -d: -f6)
    val_sinr=$(echo "$parsed" | cut -d: -f7)
    
    log "DEBUG" "Parsed - Mode: $curr_mode, MCC: $mcc, MNC: $mnc, Band: $band"
else
    log "WARN" "No serving cell info received, using defaults"
    curr_mode=""
    mcc=""
    mnc=""
    band=""
    rsrq=""
    rsrp=""
    val_sinr=""
fi

# Convert CURR_MODE to RAT code
# Use substring/pattern matching to handle mode variations (5G, 5GDUPLEX, 5G-NSA, etc.)
if echo "$curr_mode" | grep -qi "5G"; then
    rat="11"  # 5G/NR (includes 5G, 5GDUPLEX, 5G-NSA, etc.)
elif echo "$curr_mode" | grep -qi "EN-DC"; then
    rat="13"  # LTE + NR dual connectivity
elif echo "$curr_mode" | grep -qi "LTE"; then
    rat="7"   # LTE
else
    rat=""    # Unknown mode - don't include in output
fi

# Construct operator string
if [ -n "$mcc" ] && [ -n "$mnc" ]; then
    operator="${mcc}${mnc}"
else
    operator=""  # Changed: empty instead of "No operator detected"
fi

# Calculate SNR if available
snr=""
if [ -n "$val_sinr" ] && echo "$val_sinr" | grep -qE '^-?[0-9]+$'; then
    snr=$(awk "BEGIN {printf \"%.1f\", $val_sinr / 10}")
fi

# Get interface of modem
iface=$(uci -q get network.wan.device)
if [ -z "$iface" ] || [ "$iface" = "br-lan" ]; then
    # Try to detect interface from USB device tree
    bus=$(grep -m1 "5G Module" -B4 /sys/kernel/debug/usb/devices 2>/dev/null | grep -m1 "Bus=" | sed -nE 's/.*Bus=0*([0-9]+).*/\1/p')
    lev=$(grep -m1 "5G Module" -B4 /sys/kernel/debug/usb/devices 2>/dev/null | grep -m1 "Lev=" | sed -nE 's/.*Lev=0*([0-9]+).*/\1/p')
    prnt=$(grep -m1 "5G Module" -B4 /sys/kernel/debug/usb/devices 2>/dev/null | grep -m1 "Prnt=" | sed -nE 's/.*Prnt=0*([0-9]+).*/\1/p')
    port=$(grep -A20 "5G Module" /sys/kernel/debug/usb/devices 2>/dev/null | grep -E "Driver=(cdc_ether|qmi_wwan|cdc_mbim)" | head -n 1 | sed 's/.*If#=\s*\([0-9]*\).*/\1/')
    driver=$(awk '/5G Module/{flag=1} flag; /^$/{flag=0}' /sys/kernel/debug/usb/devices 2>/dev/null \
        | grep "Driver=" | grep -E "cdc|qmi" | grep -v "option" -m1 \
        | sed -nE 's/.*Driver=([a-zA-Z0-9_+-]+).*/\1/p')
    
    if [ -n "$bus" ] && [ -n "$driver" ] && [ -n "$port" ]; then
        id="${bus}-${lev}:${prnt}.${port}"
        iface=$(ls "/sys/bus/usb/drivers/$driver/$id/net" 2>/dev/null | head -n 1)
    fi
fi

[ -z "$iface" ] && [ -d /sys/class/net/usb0 ] && iface="usb0"
[ -z "$iface" ] && [ -d /sys/class/net/wwan0 ] && iface="wwan0"

proto=""
ip=""
subnet=""
bcast=""
hwaddr=""
gateway=""

if [ -n "$iface" ]; then
    if [ "$(uci -q get network.wan.device)" = "$iface" ]; then
        proto=$(uci -q get network.wan.proto)
    fi

    # Get network info of interface
    ip=$(ifconfig "$iface" 2>/dev/null | grep -i "inet addr" | awk -F ':' '{print $2}' | awk '{print $1}' | head -n 1)
    subnet=$(ifconfig "$iface" 2>/dev/null | grep -i "mask" | awk -F ':' '{print $4}' | head -n 1)
    bcast=$(ifconfig "$iface" 2>/dev/null | grep -i "bcast" | awk -F ':' '{print $3}' | awk '{print $1}' | head -n 1)
    hwaddr=$(ifconfig "$iface" 2>/dev/null | grep -i "hwaddr" | awk '{print $5}' | head -n 1)
    routeIf=$(ip route | grep -i "default via" | awk '{print $5}' | head -n 1)
    if [ "$routeIf" = "$iface" ]; then
        gateway=$(ip route | grep -i "default via" | awk '{print $3}' | head -n 1)
    fi
fi

# Get SIM information
sim1_iccid=$(extract_json_value "$ICCID_FILE_1" "iccid" "")
sim2_iccid=$(extract_json_value "$ICCID_FILE_2" "iccid" "")

# SRM810 Slot Detection via AT^SIMSLOT?
log "INFO" "Detecting SIM slot..."
slot_resp=$(at_cmd "AT^SIMSLOT?" 2)
cur_slot="1"
if echo "$slot_resp" | grep -q "0,0,1,1"; then
    cur_slot="2"
fi

# Determine ready status only after all data has been updated and verified
if check_internet "$iface"; then
    status="ready"
else
    status="configuring"
fi

# Get model name
model=$(cat /tmp/modem_model 2>/dev/null || echo "SRM810")

# Build JSON output incrementally with validation
json_output=""
json_output=$(add_json_field "$json_output" "model" "$model")
json_output=$(add_json_field "$json_output" "status" "$status")
json_output=$(add_json_field "$json_output" "operator" "$operator")
json_output=$(add_json_field "$json_output" "rat" "$rat")
json_output=$(add_json_field "$json_output" "iface" "$iface")
json_output=$(add_json_field "$json_output" "ip" "$ip")
json_output=$(add_json_field "$json_output" "proto" "$proto")
json_output=$(add_json_field "$json_output" "subnet" "$subnet")
json_output=$(add_json_field "$json_output" "bcast" "$bcast")
json_output=$(add_json_field "$json_output" "hwaddr" "$hwaddr")
json_output=$(add_json_field "$json_output" "gateway" "$gateway")
json_output=$(add_json_field "$json_output" "mcc" "$mcc")
json_output=$(add_json_field "$json_output" "mnc" "$mnc")
json_output=$(add_json_field "$json_output" "band" "$band")
json_output=$(add_json_field "$json_output" "rsrp" "$rsrp")
json_output=$(add_json_field "$json_output" "rsrq" "$rsrq")
json_output=$(add_json_field "$json_output" "snr" "$snr")
json_output=$(add_json_field "$json_output" "sim1iccid" "$sim1_iccid")
json_output=$(add_json_field "$json_output" "sim2iccid" "$sim2_iccid")
json_output=$(add_json_field "$json_output" "curSlot" "$cur_slot")

# Wrap in braces
json_output="{${json_output}}"

echo "$json_output" > "$STATUS_FILE"
echo "$json_output"

if [ ! -L "$STATS_LINK" ]; then
    ln -s "$STATUS_FILE" "$STATS_LINK"
fi
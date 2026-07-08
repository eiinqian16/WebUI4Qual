#!/bin/sh

MODEM_DEV="/dev/ttyUSB2"
APN_DB="/www/webUI/db/apn-db.json"
LOG_FILE="/tmp/auto_config.log"
LOCK_FILE="/tmp/modem.lock"
PID_FILE="/tmp/srm810_auto.pid"

log() { 
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE" >&2
}

# Ensure only one instance is running
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        exit 0
    fi
fi
echo $$ > "$PID_FILE"
trap "rm -f $PID_FILE" EXIT

# CRITICAL: Clean up any lingering processes that might lock the serial port
cleanup_serial_port() {
    log "Cleaning up serial port locks..."
    
    # Kill any processes using the device
    pgrep -f "monitor_sim.sh" 2>/dev/null | xargs -r kill -9 2>/dev/null
    pgrep -f "cat.*ttyUSB" 2>/dev/null | xargs -r kill -9 2>/dev/null
    pgrep -f "microcom" 2>/dev/null | xargs -r kill -9 2>/dev/null
    
    # Wait for processes to fully terminate
    sleep 2
    
    # Clear any leftover lock files
    rm -f "$LOCK_FILE" 2>/dev/null
    
    log "Serial port cleanup complete"
}

# Flush serial buffer to remove stale data
flush_serial_buffer() {
    log "Flushing serial buffer..."
    
    # Try to clear the buffer by reading any pending data with a short timeout
    timeout 1 cat < "$MODEM_DEV" 2>/dev/null > /dev/null || true
    
    sleep 1
    log "Buffer flush complete"
}

# AT command using microcom with better error handling
at_cmd() {
    local cmd="$1"
    local timeout="${2:-3}"
    local max_retries=2
    local retry=0
    local response=""
    
    [ -c "$MODEM_DEV" ] || {
        log "ERROR: Device $MODEM_DEV not found"
        return 1
    }

    while [ $retry -lt $max_retries ]; do
        # Use lock file to prevent collision
        touch "$LOCK_FILE"
        exec 8>"$LOCK_FILE"
        
        if flock -x 8; then
            # Small delay to ensure device is ready
            sleep 1
            
            # Convert timeout to milliseconds for microcom
            local ms=$((timeout * 1000))
            
            # Send command through microcom with explicit timeout
            response=$(echo -e "$cmd\r" | microcom -t "$ms" "$MODEM_DEV" 2>/dev/null | tr -d '\r')
            
            flock -u 8
            exec 8>&-

            if [ -n "$response" ]; then
                log "Got response: ${response:0:80}..."
                echo "$response"
                return 0
            else
                log "No response from command: $cmd (attempt $((retry + 1))/$max_retries)"
            fi
        else
            log "Failed to acquire lock (attempt $((retry + 1))/$max_retries)"
            exec 8>&-
        fi

        retry=$((retry + 1))
        # Longer delay between retries
        if [ $retry -lt $max_retries ]; then
            sleep 2
        fi
    done

    log "FAILED: No response after $max_retries attempts for: $cmd"
    return 1
}

get_iface() {
    for i in /sys/class/net/*; do
        dev=$(basename "$i")
        path=$(readlink -f "$i/device" 2>/dev/null)
        if echo "$path" | grep -qE "usb|cdc|qmi|mbim|rndis"; then
            echo "$dev"
            return 0
        fi
    done
}

setup_iface() {
    local iface=$(get_iface)
    
    if [ -z "$iface" ]; then
        log "ERROR: No modem interface found"
        return 1
    fi
    
    log "Setting up interface: $iface"
    
    if [ -z "$(uci get network.wan 2>/dev/null)" ]; then
        uci set network.wan=interface
    fi

    uci set network.wan.device="$iface"
    uci set network.wan.proto="dhcp"
    uci commit network
    
    log "Restarting network service..."
    /etc/init.d/network restart
    
    return 0
}

# Detect the PLMN (MCC+MNC) from the modem
detect_plmn() {
    local plmn=""
    
    log "Detecting PLMN from modem..."
    
    # Try AT+SGCELLINFOEX? to get MCC/MNC (SRM810 specific)
    local resp=$(at_cmd "AT+SGCELLINFOEX?" 3)
    
    if [ -n "$resp" ]; then
        log "SGCELLINFOEX response received"
        
        # Normalize response (remove newlines and extra spaces)
        local normalized=$(echo "$resp" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')
        
        # Extract MCC and MNC using flexible regex
        local mcc=$(echo "$normalized" | grep -oE "MCC:[[:space:]]*[0-9]{3}" | grep -oE "[0-9]{3}$")
        local mnc=$(echo "$normalized" | grep -oE "MNC:[[:space:]]*[0-9]{2,3}" | grep -oE "[0-9]{2,3}$")
        
        # Extract CURR_MODE and verify acquisition configuration
        # Extract value after CURR_MODE: up to the next comma or space
        local curr_mode=$(echo "$normalized" | grep -oE "CURR_MODE:[[:space:]]*[^, ]+" | cut -d: -f2 | tr -d ' ')
        
        if [ -n "$curr_mode" ]; then
            log "Detected CURR_MODE: $curr_mode"
            local expected_acq=""
            case "$curr_mode" in
                *EN-DC*) expected_acq="0304" ;;
                *5G*)    expected_acq="0403" ;;
                *LTE*)   expected_acq="03" ;;
            esac

            if [ -n "$expected_acq" ]; then
                local syscfg_resp=$(at_cmd "AT^SYSCFGEX?" 3)
                # Extract the actual acquisition mode (first parameter, which is quoted)
                local actual_acq=$(echo "$syscfg_resp" | grep -oE '"[0-9A-F]+"' | head -1 | tr -d '"')
                
                if [ "$actual_acq" != "$expected_acq" ]; then
                    log "CHECK: Acquisition mode mismatch for $curr_mode (Expected: $expected_acq, Current: $actual_acq)"

                    # Extract all parameters from the current SYSCFGEX response to preserve them
                    # The response format is typically: ^SYSCFGEX: "P1",P2,P3,P4,P5,P6,P7,"P8",P9
                    # P1 is the acquisition mode, P8 is the NR_EXT mask (can contain colons and be quoted)
                    local params_str=$(echo "$syscfg_resp" | sed 's/^[^:]*:[[:space:]]*//')
                    local param2=$(echo "$params_str" | cut -d',' -f2 | tr -d ' ')
                    local param3=$(echo "$params_str" | cut -d',' -f3 | tr -d ' ')
                    local param4=$(echo "$params_str" | cut -d',' -f4 | tr -d ' ')
                    local param5=$(echo "$params_str" | cut -d',' -f5 | tr -d ' ')
                    local param6=$(echo "$params_str" | cut -d',' -f6 | tr -d ' ')
                    local param7=$(echo "$params_str" | cut -d',' -f7 | tr -d ' ')
                    local param8=$(echo "$params_str" | cut -d',' -f8 | tr -d '" ') # Remove quotes and spaces from NR_EXT mask
                    local param9=$(echo "$params_str" | cut -d',' -f9 | tr -d ' ')

                    # Construct the new command, changing only the first parameter (acquisition mode)
                    local new_syscfg_cmd="AT^SYSCFGEX=\"$expected_acq\",$param2,$param3,$param4,$param5,$param6,$param7,\"$param8\",$param9"
                    log "INFO: Correcting acquisition mode: $new_syscfg_cmd"
                    local set_resp=$(at_cmd "$new_syscfg_cmd" 5)
                    if echo "$set_resp" | grep -q "OK"; then
                        log "INFO: Acquisition mode updated to $expected_acq successfully."
                    else
                        log "ERROR: Failed to update acquisition mode. Modem response: $set_resp"
                    fi
                else
                    log "CHECK: Acquisition mode is correct for $curr_mode: $actual_acq"
                fi
            fi
        fi

        if [ -n "$mcc" ] && [ -n "$mnc" ]; then
            plmn="${mcc}${mnc}"
            log "Detected PLMN: $plmn (MCC: $mcc, MNC: $mnc)"
            echo "$plmn"
            return 0
        fi
    fi
    
    # Fallback: Try AT+COPS? to get operator code
    log "Fallback to AT+COPS? for operator detection"
    local cops_resp=$(at_cmd "AT+COPS?" 3)
    
    if [ -n "$cops_resp" ]; then
        log "COPS response received"
        
        # Extract AcT (last parameter) and verify acquisition configuration
        local act=$(echo "$cops_resp" | awk -F',' '{print $NF}' | tr -d ' \n\r')
        if [ -n "$act" ]; then
            local expected_acq=""
            case "$act" in
                11) expected_acq="0403" ;; # 5G
                13) expected_acq="0304" ;; # EN-DC
                7)  expected_acq="03" ;;   # LTE
            esac

            if [ -n "$expected_acq" ]; then
                local syscfg_resp=$(at_cmd "AT^SYSCFGEX?" 3)
                local actual_acq=$(echo "$syscfg_resp" | grep -oE '"[0-9A-F]+"' | head -1 | tr -d '"')
                
                if [ "$actual_acq" != "$expected_acq" ]; then
                    log "CHECK: Acquisition mode mismatch for tech $act (Expected: $expected_acq, Current: $actual_acq)"

                    # Extract all parameters from the current SYSCFGEX response to preserve them
                    local params_str=$(echo "$syscfg_resp" | sed 's/^[^:]*:[[:space:]]*//')
                    local param2=$(echo "$params_str" | cut -d',' -f2 | tr -d ' ')
                    local param3=$(echo "$params_str" | cut -d',' -f3 | tr -d ' ')
                    local param4=$(echo "$params_str" | cut -d',' -f4 | tr -d ' ')
                    local param5=$(echo "$params_str" | cut -d',' -f5 | tr -d ' ')
                    local param6=$(echo "$params_str" | cut -d',' -f6 | tr -d ' ')
                    local param7=$(echo "$params_str" | cut -d',' -f7 | tr -d ' ')
                    local param8=$(echo "$params_str" | cut -d',' -f8 | tr -d '" ')
                    local param9=$(echo "$params_str" | cut -d',' -f9 | tr -d ' ')

                    if [ -n "$param2" ]; then
                        local new_syscfg_cmd="AT^SYSCFGEX=\"$expected_acq\",$param2,$param3,$param4,$param5,$param6,$param7,\"$param8\",$param9"
                        log "INFO: Correcting acquisition mode via COPS check: $new_syscfg_cmd"
                        local set_resp=$(at_cmd "$new_syscfg_cmd" 5)
                        if echo "$set_resp" | grep -q "OK"; then
                            log "INFO: Acquisition mode updated successfully."
                        else
                            log "ERROR: Failed to update acquisition mode."
                        fi
                    else
                        log "ERROR: Could not parse existing SYSCFGEX parameters for correction."
                    fi
                else
                    log "CHECK: Acquisition mode is correct for tech $act: $actual_acq"
                fi
            fi
        fi

        # Extract numeric operator code (5-6 digits: MCC+MNC)
        # Format: +COPS: <mode>,<format>,<oper>[,<AcT>]
        # When format=2 (numeric), oper is the PLMN
        plmn=$(echo "$cops_resp" | grep -oE '[0-9]{5,6}' | head -1)
        
        if [ -n "$plmn" ] && [ ${#plmn} -ge 5 ]; then
            log "Detected PLMN from COPS: $plmn"
            echo "$plmn"
            return 0
        fi
    fi
    
    log "ERROR: Could not detect PLMN from modem"
    return 1
}

# Look up APN from database based on detected PLMN
get_apn() {
    local plmn="$1"
    
    if [ -z "$plmn" ]; then
        log "ERROR: No PLMN provided for APN lookup"
        echo "internet"
        return 1
    fi
    
    log "Looking up APN for PLMN: $plmn"
    
    local apn=""
    
    if [ -f "$APN_DB" ]; then
        # Try exact PLMN match first
        apn=$(jsonfilter -i "$APN_DB" -e "@[\"$plmn\"].APNs.LTE.apn" 2>/dev/null)
        
        if [ -z "$apn" ]; then
            # Try NR5G/5G APN
            apn=$(jsonfilter -i "$APN_DB" -e "@[\"$plmn\"].APNs.NR5G.apn" 2>/dev/null)
        fi
        
        if [ -n "$apn" ]; then
            log "Found APN in database: $apn"
            echo "$apn"
            return 0
        else
            log "WARNING: No APN found in database for PLMN: $plmn"
        fi
    else
        log "WARNING: APN database not found at $APN_DB"
    fi
    
    # Default fallback
    log "Using default APN: internet"
    echo "internet"
    return 1
}

wait_for_serving_cell() {
    local max_scans=20
    local scan_attempt=0
    log "Waiting for SRM810 to register on network..."

    while [ $scan_attempt -lt $max_scans ]; do
        scan_attempt=$((scan_attempt + 1))
        
        # Check if modem is responding and has registered
        local resp=$(at_cmd "AT+CPIN?" 3)
        
        log "Scan attempt $scan_attempt: CPIN response: ${resp:0:60}"
        
        # If modem responds with READY, it has registered
        if echo "$resp" | grep -qi "READY"; then
            log "SUCCESS: Modem registered on network"
            return 0
        fi
        
        if echo "$resp" | grep -q "+CME ERROR: 10"; then
            log "ERROR: No SIM detected (+CME ERROR: 10)"
            return 1
        fi

        sleep 3
    done
    
    log "ERROR: Modem failed to register after $max_scans attempts"
    return 1
}

initialize_connection() {
    local apn="$1"
    log "Initializing SRM810 connection with APN: $apn"

    # First, configure the PDP context
    log "Step 1: Configuring PDP context with APN..."
    local resp1=$(at_cmd "AT+CGDCONT=1,\"IPV4V6\",\"$apn\"" 3)
    [ -n "$resp1" ] && log "CGDCONT response: ${resp1:0:80}" || log "CGDCONT: no response"
    
    sleep 1
    
    # Initialize with cgpaddr then dial up as per SRM810 requirements
    at_cmd "AT+CGPADDR=1" 3

    log "Step 2: Activating NDIS data connection..."
    local resp2=$(at_cmd "AT^NDISDUP=1,1,\"$apn\"" 5)
    [ -n "$resp2" ] && log "NDISDUP response: ${resp2:0:80}" || log "NDISDUP: no response"
    
    sleep 2
    
    return 0
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

log "Starting SRM810 Auto Configuration..."

cleanup_serial_port

flush_serial_buffer

sleep 2

if wait_for_serving_cell; then
    # Detect PLMN from modem
    PLMN=$(detect_plmn)
    
    if [ -n "$PLMN" ]; then
        # Get APN based on detected PLMN
        APN=$(get_apn "$PLMN")
        log "Using PLMN: $PLMN, APN: $APN"
        
        initialize_connection "$APN"
        setup_iface

        # Verify connection with retries
        retry_count=0
        while [ $retry_count -lt 3 ]; do
            sleep 10
            if check_internet; then
                log "SUCCESS: Internet connection established"
                break
            fi
            retry_count=$((retry_count + 1))
            log "Internet check failed. Retrying connection ($retry_count/3)..."
            initialize_connection "$APN"
        done
    else
        log "ERROR: Could not detect PLMN from modem"
    fi
else
    log "ERROR: Failed to register on network."
fi
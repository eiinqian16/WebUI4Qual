#! /bin/sh

MODEM_DEV=/dev/ttyUSB2
ICCID_FILE="/tmp/modem_iccid"
LOCK_FILE="/tmp/modem.lock"

at_cmd() {
    local cmd="$1"
    local timeout="${2:-2}"
    local max_retries=3
    local retry=0
    local response=""
    
    [ -c "$MODEM_DEV" ] || return 1

    while [ $retry -lt $max_retries ]; do
        # Use lock file to prevent collision with background status scripts
        touch "$LOCK_FILE"
        exec 8>"$LOCK_FILE"
        if flock -x 8; then
            # Convert timeout to milliseconds for microcom
            local ms=$((timeout * 1000))
            response=$(echo -e "$cmd\r" | microcom -t "$ms" "$MODEM_DEV" 2>/dev/null | tr -d '\r')
            
            flock -u 8
            exec 8>&-

            if [ -n "$response" ]; then
                echo "$response"
                return 0
            fi
        else
            exec 8>&-
        fi

        retry=$((retry + 1))
        # Small delay between retries to let the buffer clear
        [ $retry -lt $max_retries ] && sleep 1
    done

    echo "$response"
    return 1
}

save_iccid() {
    local slot=$1
    local iccid=""
    local retry=0
    
    echo "Reading ICCID for Slot $slot..."
    
    # Wait a bit for SIM to fully initialize before reading ICCID
    sleep 3
    
    while [ $retry -lt 8 ]; do
        # Using AT+ICCID for SRM810
        local resp=$(at_cmd "AT+ICCID" 4)
        log_msg "DEBUG: ICCID response: $resp"

        if echo "$resp" | grep -q "+CME ERROR: 10"; then
            echo "{\"slot\":$slot,\"iccid\":\"NA\"}" > "${ICCID_FILE}_${slot}"
            echo "ERROR: No SIM detected in Slot $slot (+CME ERROR: 10)" >&2
            return 1
        fi

        iccid=$(echo "$resp" | grep -i "+ICCID:" | sed 's/.*+ICCID:[[:space:]]*//' | tr -d '[:space:]')

        # Valid ICCID is typically 19-20 digits
        if [ -n "$iccid" ] && [ ${#iccid} -ge 15 ] && [ ${#iccid} -le 22 ]; then
            echo "{\"slot\":$slot,\"iccid\":\"$iccid\"}" > "${ICCID_FILE}_${slot}"
            echo "Successfully saved ICCID for Slot $slot: $iccid"
            return 0
        fi
        
        retry=$((retry + 1))
        echo "ICCID not ready, retrying ($retry/8)..."
        sleep 3
    done

    echo "{\"slot\":$slot,\"iccid\":\"NA\"}" > "${ICCID_FILE}_${slot}"
    echo "Warning: Could not read ICCID for Slot $slot after $retry attempts."
    return 1
}

wait_for_sim_ready() {
    local slot=$1
    local max_wait=30
    local elapsed=0
    
    echo "Waiting for SIM in Slot $slot (CPIN check)..."
    
    while [ $elapsed -lt $max_wait ]; do
        local resp=$(at_cmd "AT+CPIN?" 3)
        echo "DEBUG: CPIN check: $resp" >&2
        
        if echo "$resp" | grep -qi "READY"; then
            echo "SIM in Slot $slot is ready"
            return 0
        fi

        if echo "$resp" | grep -q "+CME ERROR: 10"; then
            echo "ERROR: No SIM detected in Slot $slot (+CME ERROR: 10)" >&2
            return 1
        fi

        sleep 2
        elapsed=$((elapsed + 2))
        echo "Waiting... ($elapsed/$max_wait seconds)"
    done
    
    echo "Warning: SIM in Slot $slot not ready after ${max_wait}s"
    return 1
}

switch_to_default_slot() {
    local iccid1=$(grep -o '"iccid":"[^"]*"' /tmp/modem_iccid_1 | cut -d'"' -f4)
    local iccid2=$(grep -o '"iccid":"[^"]*"' /tmp/modem_iccid_2 | cut -d'"' -f4)

    local target_slot=1

    echo "Status: Slot 1 ICCID='$iccid1', Slot 2 ICCID='$iccid2'"

    if [ -n "$iccid1" ] && [ "$iccid1" != "NA" ]; then
        echo "Slot 1 has a valid SIM. Choosing Slot 1."
        target_slot=1
    elif [ -n "$iccid2" ] && [ "$iccid2" != "NA" ]; then
        echo "Slot 1 is empty or invalid, but Slot 2 has a valid SIM. Choosing Slot 2."
        target_slot=2
    else
        echo "No valid SIM detected in either slot. Defaulting to Slot 1."
        target_slot=1
    fi

    echo "Best slot determined: $target_slot"

    at_cmd "AT^SIMSLOT=$target_slot"
    wait_for_sim_ready "$target_slot"
}

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /tmp/sim_det.log
}

check_and_switch_sim() {
    # 1. Check which sim slot it is currently in
    at_cmd "AT^SIMSLOT=1" 10 >/dev/null
    local slot_resp=$(at_cmd "AT^SIMSLOT?" 3)
    log_msg "DEBUG: Current slot response: $slot_resp"
    
    local current_slot=1
    if echo "$slot_resp" | grep -q "1,1,0,0"; then
        current_slot=1
    elif echo "$slot_resp" | grep -q "0,0,1,1"; then
        current_slot=2
    fi
    
    echo "Current Slot: $current_slot"
    
    # 2. Check ICCID of current slot (executed before any slot change)
    save_iccid "$current_slot"

    # 3. Change sim slot
    local other_slot=$([ "$current_slot" = "1" ] && echo 2 || echo 1)
    echo "Switching to Slot $other_slot..."
    at_cmd "AT^SIMSLOT=$other_slot" 3

    # 4. Wait around 10 seconds before checking at+cpin
    echo "Waiting 10 seconds for modem to reinitialize after slot switch..."
    sleep 10
    
    # 5. Check at+cpin to see if modem ready and 6. check iccid of the second slot
    wait_for_sim_ready "$other_slot"
    save_iccid "$other_slot"
}

# Main

# Strip hidden carriage returns, spaces, or tabs from the device path
MODEM_DEV=$(echo "$MODEM_DEV" | tr -d ' \t\r\n')

# CRITICAL: Stop the monitor script to prevent serial port contention
pgrep -f "monitor_sim.sh" | xargs -r kill -9
pgrep -f "cat $MODEM_DEV" | xargs -r kill -9
sleep 2

wait_count=0
while [ ! -c "$MODEM_DEV" ] && [ $wait_count -lt 30 ]; do
    sleep 1
    wait_count=$((wait_count + 1))
done

[ ! -c "$MODEM_DEV" ] && echo "ERROR: No modem found at $MODEM_DEV" && exit 1

check_and_switch_sim
switch_to_default_slot

echo "SIM detection complete. Check files:"
ls -l "${ICCID_FILE}_"* 2>/dev/null || echo "No ICCID files created"
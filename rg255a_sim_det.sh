#! /bin/sh

MODEM_DEV=/dev/ttyUSB2
ICCID_FILE="/tmp/modem_iccid"
LOCK_FD=200

# Use a lock to prevent concurrent access
lock_modem() {
    eval "exec $LOCK_FD>$MODEM_DEV"
    flock -x $LOCK_FD
}

unlock_modem() {
    flock -u $LOCK_FD
    eval "exec $LOCK_FD>&-"
}

at_cmd() {
    local cmd="$1"
    local timeout="${2:-5}"
    local response=""
    
    [ -c "$MODEM_DEV" ] || return 1
    exec 3<> "$MODEM_DEV" 2>/dev/null || return 1

    # Drain existing data from the serial buffer to prevent command/response mismatch
    timeout 1 cat <&3 >/dev/null 2>&1

    printf "%s\r\n" "$cmd" >&3
    response=$(timeout "$timeout" cat <&3 2>/dev/null | tr -d '\r')
    exec 3>&-
    
    if [ -z "$response" ] && [ -c "$MODEM_DEV" ]; then
        echo "Modem at $MODEM_DEV unresponsive. Rebinding USB interface 2-1..." >&2
        echo "2-1" > /sys/bus/usb/drivers/usb/unbind 2>/dev/null
        sleep 2
        echo "2-1" > /sys/bus/usb/drivers/usb/bind 2>/dev/null
        # Allow time for device nodes to be recreated
        sleep 10
    fi

    echo "$response"
    return 0
}

save_iccid() {
    local slot=$1
    local iccid=""
    local retry=0
    
    echo "Reading ICCID for Slot $slot..."
    
    # Wait a bit for SIM to fully initialize before reading ICCID
    sleep 3
    
    while [ $retry -lt 8 ]; do
        # Try AT+ICCID first
        local resp=$(at_cmd "AT+ICCID" 6)
        echo "DEBUG: ICCID response: $resp" >&2
        
        iccid=$(echo "$resp" | grep -i "ICCID:" | sed 's/.*ICCID:[[:space:]]*//' | tr -dc '0-9')
        
        # If ICCID is empty, try AT+QCCID
        if [ -z "$iccid" ] || [ ${#iccid} -lt 10 ]; then
            resp=$(at_cmd "AT+QCCID" 6)
            echo "DEBUG: QCCID response: $resp" >&2
            iccid=$(echo "$resp" | grep -i "QCCID:" | sed 's/.*QCCID:[[:space:]]*//' | tr -dc '0-9')
        fi
        
        # Also try AT+CIMI (IMSI - can be used as fallback identifier)
        if [ -z "$iccid" ] || [ ${#iccid} -lt 10 ]; then
            resp=$(at_cmd "AT+CIMI" 6)
            echo "DEBUG: CIMI response: $resp" >&2
            iccid=$(echo "$resp" | tr -dc '0-9' | head -c 20)
        fi

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
    
    local raw_slot=$(at_cmd "AT+QDSIM?" 3 | grep -oE "[0-1]" | head -n 1)
    local current_slot=$([ "$raw_slot" = "0" ] && echo 1 || echo 2)
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

    # Execute switch only if necessary
    if [ "$current_slot" != "$target_slot" ]; then
        echo "Switching from slot $current_slot to slot $target_slot ..."
        # Slot 1 = 0, Slot 2 = 1
        local cmd_val=$([ "$target_slot" = "1" ] && echo 0 || echo 1)
        at_cmd "AT+QDSIM=$cmd_val"
        wait_for_sim_ready "$target_slot"
    else
        echo "Modem is already on the best available slot ($target_slot)."
    fi
}

check_and_switch_sim() {
    # Get current slot
    local slot_resp=$(at_cmd "AT+QDSIM?" 3)
    echo "DEBUG: Current slot response: $slot_resp" >&2
    
    local current_slot=1
    # QDSIM: 0 is Slot 1, QDSIM: 1 is Slot 2
    if echo "$slot_resp" | grep -qi "QDSIM: 1"; then
        current_slot=2
    fi
    
    echo "Current Slot: $current_slot"
    
    # Check if current slot has SIM
    if wait_for_sim_ready "$current_slot"; then
        echo "SIM found in Slot $current_slot"
        save_iccid "$current_slot"
    else
        echo "No SIM found in Slot $current_slot"
    fi

    # Switch to other slot
    local other_slot=$([ "$current_slot" = "1" ] && echo 2 || echo 1)
    local other_cmd_val=$([ "$current_slot" = "1" ] && echo 1 || echo 0)
    echo "Switching to Slot $other_slot (Command value: $other_cmd_val)..."
    
    at_cmd "AT+QDSIM=$other_cmd_val" 5
    # Brief pause for the modem to register the physical SIM line switch
    sleep 5

    # Modem needs time to switch and reinitialize
    echo "Waiting for modem to reinitialize after slot switch..."
    sleep 10
    
    if wait_for_sim_ready "$other_slot"; then
        echo "SIM found in Slot $other_slot"
        save_iccid "$other_slot"
    else
        echo "No SIM found in Slot $other_slot"
        # Optionally switch back
        # at_cmd "AT+QDSIM=$current_slot" 3
    fi
}

# Main

# Strip hidden carriage returns, spaces, or tabs from the device path
MODEM_DEV=$(echo "$MODEM_DEV" | tr -d ' \t\r\n')

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
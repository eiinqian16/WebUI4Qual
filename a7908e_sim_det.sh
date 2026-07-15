#! /bin/sh

MODEM_DEV=/dev/ttyUSB2
ICCID_FILE="/tmp/modem_iccid"
LOCK_FD=200
GPIO_PATH="/sys/class/gpio/gpio22"

setup_gpio() {
    if [ ! -d "$GPIO_PATH" ]; then
        echo 22 > /sys/class/gpio/export 2>/dev/null
        echo out > "$GPIO_PATH/direction" 2>/dev/null
    fi
}

get_current_slot() {
    setup_gpio
    local val=$(cat "$GPIO_PATH/value")
    [ "$val" = "0" ] && echo 1 || echo 2
}

set_slot_and_reboot() {
    local target=$1
    local val=$([ "$target" = "1" ] && echo 0 || echo 1)
    setup_gpio
    echo "$val" > "$GPIO_PATH/value"
    echo "Switched GPIO to $val (Slot $target). Rebooting modem..."
    at_cmd "AT+CFUN=1,1" 3 > /dev/null
    
    # Wait for device to cycle
    sleep 5
    local timeout=30
    while [ ! -c "$MODEM_DEV" ] && [ $timeout -gt 0 ]; do
        sleep 1
        timeout=$((timeout - 1))
    done
    sleep 10 # Allow modem firmware to fully initialize
}

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
    printf "%s\r\n" "$cmd" >&3
    response=$(timeout "$timeout" cat <&3 2>/dev/null | tr -d '\r')
    exec 3>&-
    
    if [ -z "$response" ] && [ -c "$MODEM_DEV" ]; then
        echo "Modem at $MODEM_DEV unresponsive. Rebinding USB interface 2-1..." >&2
        echo "2-1" > /sys/bus/usb/drivers/usb/unbind 2>/dev/null
        sleep 2
        echo "2-1" > /sys/bus/usb/drivers/usb/bind 2>/dev/null
        # Allow time for device nodes to be recreated
        sleep 8
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
        local resp=$(at_cmd "AT+CICCID" 10)
        echo "DEBUG: ICCID response: $resp" >&2
        
        iccid=$(echo "$resp" | grep -i "+ICCID:" | sed 's/.*+ICCID:[[:space:]]*//' | tr -dc '0-9')

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
    
    local current_slot=$(get_current_slot)
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
        set_slot_and_reboot "$target_slot"
    else
        echo "Modem is already on the best available slot ($target_slot)."
    fi
}

check_and_switch_sim() {
    local current_slot=$(get_current_slot)
    
    echo "Current Slot: $current_slot"
    
    # Check if current slot has SIM
    if wait_for_sim_ready "$current_slot"; then
        echo "SIM found in Slot $current_slot"
        save_iccid "$current_slot"
    else
        echo "No SIM found in Slot $current_slot"
    fi

    # Switch to other slot
    local other_slot=$([ "$current_slot" = "1" ] && echo "2" || echo "1")
    echo "Temporarily switching to Slot $other_slot to detect SIM..."

    set_slot_and_reboot "$other_slot"
    
    if wait_for_sim_ready "$other_slot"; then
        echo "SIM found in Slot $other_slot"
        save_iccid "$other_slot"
    else
        echo "No SIM found in Slot $other_slot"
        # Optionally switch back
        # at_cmd "AT+QUIMSLOT=$current_slot" 3
    fi
}

# Main

# Strip hidden carriage returns, spaces, or tabs from the device path
MODEM_DEV=$(echo "$MODEM_DEV" | tr -d ' \t\r\n')

wait_count=0
# Increase wait time to 30 seconds to handle slow initialization on boot
while [ ! -c "$MODEM_DEV" ] && [ $wait_count -lt 30 ]; do
    sleep 1
    wait_count=$((wait_count + 1))
done

[ ! -c "$MODEM_DEV" ] && echo "ERROR: No modem found at $MODEM_DEV" && exit 1

check_and_switch_sim
switch_to_default_slot

echo "SIM detection complete. Check files:"
ls -l "${ICCID_FILE}_"* 2>/dev/null || echo "No ICCID files created"
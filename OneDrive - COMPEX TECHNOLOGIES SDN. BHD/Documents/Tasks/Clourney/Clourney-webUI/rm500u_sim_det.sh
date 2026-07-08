#!/bin/sh

MODEM_DEV=/dev/ttyUSB2
ICCID_FILE="/tmp/modem_iccid"

at_cmd() {
    local cmd="$1"
    local timeout="${2:-5}"
    local response=""

    [ -c "$MODEM_DEV" ] || return 1

    response=$(printf '%s\r\n' "$cmd" | microcom -s 115200 -t $((timeout * 1000)) "$MODEM_DEV" 2>/dev/null | tr -d '\r')

    if [ -z "$response" ] && [ -c "$MODEM_DEV" ]; then
        echo "Modem at $MODEM_DEV unresponsive. Rebinding USB interface 2-1..." >&2
        echo "2-1" > /sys/bus/usb/drivers/usb/unbind 2>/dev/null
        sleep 2
        echo "2-1" > /sys/bus/usb/drivers/usb/bind 2>/dev/null
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

    # Try AT+QCCID first
    local resp=$(at_cmd "AT+QCCID" 6)
    echo "DEBUG: QCCID response: $resp" >&2

    iccid=$(echo "$resp" | grep -i "QCCID:" | sed 's/.*QCCID:[[:space:]]*//' | tr -dc '0-9A-Fa-f')

    # Valid ICCID is typically 19-20 digits
    if [ -n "$iccid" ] && [ ${#iccid} -ge 15 ] && [ ${#iccid} -le 22 ]; then
        echo "{\"slot\":$slot,\"iccid\":\"$iccid\"}" > "${ICCID_FILE}_${slot}"
        echo "Successfully saved ICCID for Slot $slot: $iccid"
        return 0
    fi

    retry=$((retry + 1))
    echo "ICCID not ready, retrying ($retry/1)..."
    sleep 3

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
    local iccid1=""
    local iccid2=""

    [ -f "/tmp/modem_iccid_1" ] && iccid1=$(grep -o '"iccid":"[^"]*"' /tmp/modem_iccid_1 | cut -d'"' -f4)
    [ -f "/tmp/modem_iccid_2" ] && iccid2=$(grep -o '"iccid":"[^"]*"' /tmp/modem_iccid_2 | cut -d'"' -f4)

    local raw_slot=$(at_cmd "AT+QUIMSLOT?" 3 | grep -oE "[1-2]" | head -n 1)
    local current_slot=$([ "$raw_slot" = "2" ] && echo 2 || echo 1)
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

    if [ "$current_slot" != "$target_slot" ]; then
        echo "Switching from slot $current_slot to slot $target_slot ..."
        at_cmd "AT+QUIMSLOT=$target_slot" 5
        sleep 5
        wait_for_sim_ready "$target_slot"
    else
        echo "Modem is already on the best available slot ($target_slot)."
    fi
}

check_and_switch_sim() {
    local slot_resp=$(at_cmd "AT+QUIMSLOT?" 3)
    echo "DEBUG: Current slot response: $slot_resp" >&2

    local current_slot=1
    if echo "$slot_resp" | grep -qi "QUIMSLOT: 2"; then
        current_slot=2
    fi

    echo "Current Slot: $current_slot"

    if wait_for_sim_ready "$current_slot"; then
        echo "SIM found in Slot $current_slot"
        save_iccid "$current_slot"
    else
        echo "No SIM found in Slot $current_slot"
    fi

    local other_slot=$([ "$current_slot" = "1" ] && echo 2 || echo 1)
    echo "Switching to Slot $other_slot..."

    at_cmd "AT+QUIMSLOT=$other_slot" 5
    sleep 5

    echo "Waiting for modem to reinitialize after slot switch..."
    sleep 10

    if wait_for_sim_ready "$other_slot"; then
        echo "SIM found in Slot $other_slot"
        save_iccid "$other_slot"
    else
        echo "No SIM found in Slot $other_slot"
    fi
}

# Main

MODEM_DEV=$(echo "$MODEM_DEV" | tr -d ' \t\r\n')

# Check microcom is available
if ! command -v microcom >/dev/null 2>&1; then
    echo "ERROR: microcom not found" >&2
    exit 1
fi

# Check for other processes holding the port
if fuser "$MODEM_DEV" >/dev/null 2>&1; then
    echo "ERROR: $MODEM_DEV is held by another process:" >&2
    fuser -v "$MODEM_DEV" >&2
    exit 1
fi

wait_count=0
while [ ! -c "$MODEM_DEV" ] && [ $wait_count -lt 30 ]; do
    sleep 1
    wait_count=$((wait_count + 1))
done

[ ! -c "$MODEM_DEV" ] && echo "ERROR: No modem found at $MODEM_DEV" && exit 1

# Send ATE0 to disable echo, makes response parsing cleaner
at_cmd "ATE0" 3 >/dev/null

check_and_switch_sim
switch_to_default_slot

echo "SIM detection complete. Check files:"
ls -l "${ICCID_FILE}_"* 2>/dev/null || echo "No ICCID files created"
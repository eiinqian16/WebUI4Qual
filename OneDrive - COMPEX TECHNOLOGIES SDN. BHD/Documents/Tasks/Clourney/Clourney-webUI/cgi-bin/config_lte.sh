#!/bin/sh

echo "Content-type: text/plain"
echo ""

read INPUT
#INPUT="&proto=lte&apn=mycelcom4g&service=LTE&slot=0"

MODEM_DEV="/dev/ttyUSB2"

if [ -z "$MODEM_DEV" ]; then
    echo '{"error": "No modem found"}'
    exit 1
fi

echo "Detected modem port: $MODEM_DEV"

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
service=$(extract_value "service")
slot=$(extract_value "slot")

proto=${proto:-""}
apn=${apn:-""}
service=${service:-""}
slot=${slot:-""}

get_net() {
    exec 3<> "$MODEM_DEV"
    echo -e 'AT+QCFG="usbnet"\r' >&3

    # Read all available lines for up to 1 second
    resp=$(timeout 1 cat <&3 2>/dev/null || true)
    exec 3>&-

    # Extract the numeric value
    usbnet=$(echo "$resp" | grep -oE '\+QCFG: "usbnet",[0-9]+' | awk -F',' '{print $2}')

    # Fallback check
    if [ -z "$usbnet" ]; then
        echo "No response or invalid format"
    else
        echo "$usbnet"
    fi
}

set_ecm() {
    exec 3<> "$MODEM_DEV"
    echo -e 'AT+QCFG="usbnet",1\r' >&3

    resp=$(timeout 1 cat <&3 2>/dev/null || true)
    exec 3>&-
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
        echo '{"set_data_call_result_error":"PDP config failed"}'
        echo "$resp"
        return 1
    fi
}

disable_data_call() {
    exec 3<> "$MODEM_DEV"
    echo -e 'AT+QNETDEVCTL=0,1,1' >&3

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

set_pdp_context() {
    local apn="$1"
    exec 3<> "$MODEM_DEV"
    echo -e "AT+CGDCONT=1,\"IPV4V6\",\"${apn}\"\r" >&3
    sleep 1
    resp=$(timeout 1 cat <&3 2>/dev/null | tr -d '\r' || true)
    exec 3>&-

    echo "DEBUG: [$resp]" >&2

    if echo "$resp" | grep -q "OK"; then
        echo '{"set_pdp_context_result":"OK"}'
        return 0
    else
        echo '{"set_pdp_context_error":"PDP config failed"}'
        echo "$resp"
        return 1
    fi
}

enable_pdp() {
    exec 3<> "$MODEM_DEV"
    echo -e 'AT+CGACT=1,1\r' >&3

    resp=$(timeout 1 cat <&3 2>/dev/null || true)
    exec 3>&-

    if echo "$resp" | grep -q "OK"; then
        echo '{"enable_pdp_result":"OK"}'
        return 0
    else
        echo '{"enable_pdp_error":"PDP config failed"}'
        echo "$resp"
        return 1
    fi
}

set_mode_pref() {
    local service="$1"
    exec 3<> "$MODEM_DEV"
    echo -e "AT+QNWPREFCFG=\"mode_pref\",\"${service}\"\r" >&3

    resp=$(timeout 1 cat <&3 2>/dev/null || true)
    exec 3>&-

    if echo "$resp" | grep -q "OK"; then
        echo '{"set_mode_pref_result":"OK"}'
        return 0
    else
        echo '{"set_mode_pref_error":"set mode pref failed"}'
        echo "$resp"
        return 1
    fi
}

get_cur_slot() {
    # Start reading in background before sending command
    cat "$MODEM_DEV" > /tmp/modem_resp.txt &
    CAT_PID=$!
    
    sleep 1
    
    # Send command
    echo -e "AT+QDSIM?\r" > "$MODEM_DEV"
    
    # Wait a bit for response
    sleep 1
    
    # Kill the cat process
    kill $CAT_PID 2>/dev/null
    wait $CAT_PID 2>/dev/null
    
    # Read the captured response
    resp=$(cat /tmp/modem_resp.txt)
    rm -f /tmp/modem_resp.txt
    
    # Output debug to stderr so it doesn't interfere with return value
    echo "Response: $resp" >&2
    
    if echo "$resp" | grep -q "+QDSIM:"; then
        curSlot=$(echo "$resp" | grep "+QDSIM:" | awk -F: '{print $2}' | tr -d ' \r\n')
        echo "Current Slot: $curSlot" >&2
        # Return ONLY the slot number to stdout
        echo "$curSlot"
        return 0
    else
        echo '{"get_cur_slot_error":"get slot failed"}' >&2
        return 1
    fi
}

set_sim_slot() {
    local slot="$1"
    exec 3<> "$MODEM_DEV"
    echo -e "AT+QDSIM=\"${slot}\"\r" >&3

    resp=$(timeout 1 cat <&3 2>/dev/null || true)
    exec 3>&-

    if echo "$resp" | grep -q "OK"; then
        echo '{"set_sim_slot":"OK"}'
        return 0 
    else
        echo '{"set_sim_slot_error":"set sim slot failed"}'
        echo "$resp"
        return 1
    fi
}

reset_sim() {
    exec 3<> "$MODEM_DEV"
    echo -e "AT+CFUN=1,1" >&3

    resp=$(timeout 1 cat <&3 2>/dev/null || true)
    exec 3>&-

    if echo "$resp" | grep -q "OK"; then
        echo '{"sim_reset":"OK"}'
        sleep 5
        if [ -z "$MODEM_DEV" ]; then
            echo '{"error":"No modem found"}'
            exit 1
        else
            echo '{"error":"Modem reloaded"}'
        fi
    else
        echo '{"sim_reset":"failed"}'
        echo "$resp"
        return 1
    fi
}

get_iface() {
    for i in /sys/class/net/*; do
        dev=$(basename "$i")
        path=$(readlink -f "$i/device" 2>/dev/null)
        if echo "$path" | grep -qE "usb|cdc|qmi|mbim|rndis"; then
            echo "$dev"
        fi
    done
}

setup_iface() {
    iface=$(get_iface)
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
    reboot
}

#echo "$proto"
#echo "$apn"
#echo "$service"
#echo "$slot"
#echo "$(set_data_call)"
#echo "$(set_pdp_context "$apn")"
#echo "$(enable_pdp)"
#echo "$(set_mode_pref "$service")"

#main 
disable_data_call
if [ "$(get_net)" -eq 1 ]; then
    echo "ECM used"
else
    set_ecm
fi
set_pdp_context "$apn"
set_data_call
cur_slot=$(get_cur_slot)
if [ "$cur_slot" -eq "$slot" ] 2>/dev/null; then
    echo "Same slot"
else
    set_sim_slot $slot
    reset_sim
fi
setup_iface

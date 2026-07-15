#!/bin/sh

echo "Content-type: application/json"
echo ""

MODEM_DEV="/dev/ttyUSB2"
APN_DB="/www/webUI/db/apn-db.json"
LOG_FILE="/tmp/rm500u_config.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [RECOVERY] $1" >> "$LOG_FILE"
}

at_cmd() {
    local cmd="$1"
    local timeout="${2:-2}"
    local resp=""
    touch /tmp/modem.lock
    exec 8>/tmp/modem.lock
    flock -x 8
    if exec 3<> "$MODEM_DEV"; then
        read -t 1 <&3
        printf "%s\r\n" "$cmd" >&3
        resp=$(timeout "$timeout" cat <&3 2>/dev/null | tr -d '\r')
        exec 3>&-
    fi
    flock -u 8
    exec 8>&-
    echo "$resp"
}

get_iface() {
    local iface=$(ls /sys/bus/usb/drivers/cdc_ether/*/net 2>/dev/null | head -n 1)
    [ -z "$iface" ] && iface=$(ls /sys/class/net/usb* 2>/dev/null | head -n 1)
    basename "$iface" 2>/dev/null
}

# 1. Check Registration
serving=$(at_cmd 'AT+QENG="servingcell"' 3)
rat=$(echo "$serving" | grep '^+QENG: "servingcell"' | awk -F ',' '{print $3}' | tr -d '"')
mcc=$(echo "$serving" | grep '^+QENG: "servingcell"' | awk -F ',' '{print $5}' | tr -dc '0-9')
mnc=$(echo "$serving" | grep '^+QENG: "servingcell"' | awk -F ',' '{print $6}' | tr -dc '0-9')
plmn="${mcc}${mnc}"

if [ -z "$mcc" ] || [ "$mcc" = "0" ]; then
    log "Modem not registered on any cell."
    echo '{"status":"error","message":"Not registered"}'
    exit 1
fi

# 2. Verify APN config in modem
current_apn_info=$(at_cmd "AT+CGDCONT?" 2)
current_apn=$(echo "$current_apn_info" | grep "+CGDCONT: 1" | awk -F ',' '{print $3}' | tr -d '"')

# Find expected APN from DB
expected_apn=""
if [ -f "$APN_DB" ] && [ -n "$plmn" ]; then
    expected_apn=$(jsonfilter -i "$APN_DB" -e "@[\"$plmn\"].APNs.LTE.apn" 2>/dev/null)
    [ -z "$expected_apn" ] && expected_apn=$(jsonfilter -i "$APN_DB" -e "@[\"$plmn\"].APNs.NR5G.apn" 2>/dev/null)
fi

needs_reconfig=0
[ -n "$expected_apn" ] && [ "$current_apn" != "$expected_apn" ] && needs_reconfig=1

if [ "$needs_reconfig" -eq 1 ]; then
    log "APN mismatch detected (Current: $current_apn, Expected: $expected_apn). Reconfiguring..."
    at_cmd "AT+CGDCONT=1,\"IPV4V6\",\"$expected_apn\"" 2
fi

# 3. Check and Recovery PDP
pdp_status=$(at_cmd "AT+CGACT?" 2)
is_active=$(echo "$pdp_status" | grep -q "+CGACT: 1,1" && echo 1 || echo 0)

if [ "$is_active" -eq 0 ]; then
    log "PDP Context inactive. Attempting activation..."
    at_cmd "AT+CGACT=1,1" 5
    sleep 2
fi

# 4. Check Data Call (QNETDEVCTL)
data_call_resp=$(at_cmd "AT+QNETDEVCTL?" 2)
is_dialed=$(echo "$data_call_resp" | grep -q "+QNETDEVCTL: 1,1" && echo 1 || echo 0)

if [ "$is_dialed" -eq 0 ]; then
    log "Data call not active. Triggering QNETDEVCTL..."
    at_cmd "AT+QNETDEVCTL=3,1,1" 5
    sleep 2
fi

# 5. Verify interface and IP
iface=$(get_iface)
ip=$(ifconfig "$iface" 2>/dev/null | grep "inet addr" | awk -F ':' '{print $2}' | awk '{print $1}')

if [ -z "$ip" ] && [ -n "$iface" ]; then
    log "Interface $iface has no IP. Restarting network..."
    uci set network.wan.device="$iface"
    uci commit network
    /etc/init.d/network restart
    sleep 5
    ip=$(ifconfig "$iface" 2>/dev/null | grep "inet addr" | awk -F ':' '{print $2}' | awk '{print $1}')
fi

if [ -n "$ip" ]; then
    log "Recovery successful. IP assigned: $ip"
    echo "{\"status\":\"success\",\"ip\":\"$ip\",\"iface\":\"$iface\",\"apn\":\"${expected_apn:-$current_apn}\"}"
else
    log "Recovery failed to obtain IP."
    echo "{\"status\":\"failed\",\"iface\":\"$iface\",\"apn\":\"${expected_apn:-$current_apn}\"}"
fi

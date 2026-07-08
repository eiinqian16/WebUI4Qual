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

log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE" >&2
}

at_cmd() {
    local cmd="$1"
    local timeout="${2:-5}"
    local max_retries=3
    local retry=0
    local response=""

    [ -c "$MODEM_DEV" ] || { log "ERROR" "$MODEM_DEV not found"; return 1; }

    local lock_fd=9
    eval "exec $lock_fd>/tmp/modem.lock"
    flock -x "$lock_fd"

    while [ $retry -lt $max_retries ]; do
        response=$(printf '%s\r\n' "$cmd" | timeout "$timeout" microcom -s 115200 "$MODEM_DEV" 2>/dev/null | tr -d '\r')

        local cleaned=$(echo "$response" | grep -v "^${cmd}$" | grep -v '^$')

        if [ -n "$cleaned" ]; then
            eval "exec ${lock_fd}>&-"
            # Brief gap so modem can settle before next command
            sleep 1
            echo "$response"
            return 0
        fi

        retry=$((retry + 1))
        [ $retry -lt $max_retries ] && log "WARN" "No response to '$cmd', retrying ($retry/$max_retries)..."
        sleep 1
    done

    eval "exec ${lock_fd}>&-"
    sleep 0.3
    log "ERROR" "No response to '$cmd' after $max_retries attempts"
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
        log "INFO" "Searching for alternative modem devices..."
        for dev in /dev/ttyUSB* /dev/ttyACM* /dev/cdc-wdm*; do
            if [ -c "$dev" ]; then
                log "INFO" "Found potential modem device: $dev"
            fi
        done
        return 1
    fi

    if [ ! -r "$MODEM_DEV" ] || [ ! -w "$MODEM_DEV" ]; then
        log "ERROR" "Insufficient permissions for $MODEM_DEV"
        return 1
    fi

    log "INFO" "Modem device validated: $MODEM_DEV"
    return 0
}

check_internet() {
    local target_iface=$(uci -q get network.wan.device)
    [ -z "$target_iface" ] && target_iface="usb0"

    ping -I "$target_iface" -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1
}

parse_serving_cell() {
    local serving="$1"

    echo "$serving" | awk -F',' '
        /^\+QENG: "servingcell"/ {
            # Field 3 is RAT: "NR5G-SA", "LTE", or "NR5G-NSA" embedded in the servingcell line
            rat_field = $3; gsub(/"/, "", rat_field)
            if (rat_field == "NR5G-SA") {
                # +QENG: "servingcell","CONNECT","NR5G-SA","TDD",MCC,MNC,CID,PCI,TAC,ARFCN,BAND,TXPOWER,RSRP,RSRQ,SINR,...
                mcc     = $5;  gsub(/[^0-9]/, "", mcc)
                mnc     = $6;  gsub(/[^0-9]/, "", mnc)
                nr_band = $11; gsub(/[^0-9]/, "", nr_band)
                nr_rsrp = $13; gsub(/[^0-9-]/, "", nr_rsrp)
                nr_rsrq = $14; gsub(/[^0-9-]/, "", nr_rsrq)
                nr_snr  = $15; gsub(/[^0-9.-]/, "", nr_snr)
                has_sa  = 1
            } else if (rat_field == "LTE") {
                # +QENG: "servingcell","CONNECT","LTE","FDD",MCC,MNC,CID,PCI,EARFCN,BAND,UL_BW,DL_BW,TAC,RSRP,RSRQ,RSSI,SINR,...
                mcc      = $5;  gsub(/[^0-9]/, "", mcc)
                mnc      = $6;  gsub(/[^0-9]/, "", mnc)
                lte_band = $10; gsub(/[^0-9]/, "", lte_band)
                lte_rsrp = $14; gsub(/[^0-9-]/, "", lte_rsrp)
                lte_rsrq = $15; gsub(/[^0-9-]/, "", lte_rsrq)
                lte_snr  = $17; gsub(/[^0-9.-]/, "", lte_snr)
                has_lte  = 1
            }
        }
        /^\+QENG: "LTE"/ {
            # Legacy format: separate LTE line (older firmware)
            # +QENG: "LTE","FDD",MCC,MNC,CID,PCID,EARFCN,BAND,UL_BW,DL_BW,TAC,RSRP,RSRQ,RSSI,SINR,...
            mcc      = $3;  gsub(/[^0-9]/, "", mcc)
            mnc      = $4;  gsub(/[^0-9]/, "", mnc)
            lte_band = $8;  gsub(/[^0-9]/, "", lte_band)
            lte_rsrp = $12; gsub(/[^0-9-]/, "", lte_rsrp)
            lte_rsrq = $13; gsub(/[^0-9-]/, "", lte_rsrq)
            lte_snr  = $15; gsub(/[^0-9.-]/, "", lte_snr)
            has_lte  = 1
        }
        /^\+QENG: "NR5G-NSA"/ {
            # +QENG: "NR5G-NSA",MCC,MNC,PCI,RSRP,RSRQ,SINR,ARFCN,BAND,...
            nr_rsrp = $5; gsub(/[^0-9-]/, "", nr_rsrp)
            nr_rsrq = $7; gsub(/[^0-9-]/, "", nr_rsrq)
            nr_snr  = $6; gsub(/[^0-9.-]/, "", nr_snr)
            nr_band = $9; gsub(/[^0-9]/, "", nr_band)
            if (nr_band != "" && nr_band != "0") has_nsa = 1
        }
        END {
            if (has_sa) {
                rat  = "NR5G-SA"
                band = nr_band
                rsrp = nr_rsrp
                rsrq = nr_rsrq
                snr  = nr_snr
            } else if (has_lte && has_nsa) {
                rat  = "NR5G-NSA"
                band = nr_band
                rsrp = nr_rsrp
                rsrq = nr_rsrq
                snr  = nr_snr
            } else if (has_lte) {
                rat  = "LTE"
                band = lte_band
                rsrp = lte_rsrp
                rsrq = lte_rsrq
                snr  = lte_snr
            } else {
                rat  = "UNKNOWN"
            }
            print mcc ";" mnc ";" rat ";" band ";" rsrp ";" rsrq ";" snr ";" lte_band
        }
    '
}

rat_to_num() {
    case "$1" in
        "LTE")      echo "7"  ;;
        "NR5G-NSA") echo "13" ;;  # 13 = NR5G-NSA
        "NR5G-SA")  echo "11" ;;  # 11 = NR5G-SA
        *)          echo ""   ;;
    esac
}

model=$(cat /tmp/modem_model 2>/dev/null || echo "RM500U")
echo "{\"status\":\"configuring\",\"model\":\"$model\"}" > "$STATUS_FILE"

serving=$(at_cmd "AT+QENG=\"servingcell\"" 15)
log "DEBUG" "Raw serving cell: $serving"

parsed=$(parse_serving_cell "$serving")
mcc=$(echo  "$parsed" | cut -d';' -f1)
mnc=$(echo  "$parsed" | cut -d';' -f2)
qeng_rat=$(echo "$parsed" | cut -d';' -f3)
band=$(echo "$parsed" | cut -d';' -f4)
rsrp=$(echo "$parsed" | cut -d';' -f5)
rsrq=$(echo "$parsed" | cut -d';' -f6)
snr=$(echo  "$parsed" | cut -d';' -f7)
lte_band=$(echo "$parsed" | cut -d';' -f8)

rat=$(rat_to_num "$qeng_rat")
operator="${mcc}${mnc}"
[ -z "$mcc" ] && operator="No operator detected"
[ -z "$rat" ] && rat="No band found"

log "DEBUG" "Parsed: MCC=$mcc MNC=$mnc RAT=$qeng_rat($rat) BAND=$band RSRP=$rsrp RSRQ=$rsrq SNR=$snr"

# Get interface of modem
iface=$(uci -q get network.wan.device)
if [ -z "$iface" ] || [ "$iface" = "br-lan" ]; then
    bus=$(grep -m1 "Quectel" -B4 /sys/kernel/debug/usb/devices | grep -m1 "Bus=" | sed -nE 's/.*Bus=0*([0-9]+).*/\1/p')
    lev=$(grep -m1 "Quectel" -B4 /sys/kernel/debug/usb/devices | grep -m1 "Lev=" | sed -nE 's/.*Lev=0*([0-9]+).*/\1/p')
    prnt=$(grep -m1 "Quectel" -B4 /sys/kernel/debug/usb/devices | grep -m1 "Prnt=" | sed -nE 's/.*Prnt=0*([0-9]+).*/\1/p')
    port=$(grep -A20 "Quectel" /sys/kernel/debug/usb/devices | grep -E "Driver=(cdc_ether|qmi_wwan|cdc_mbim)" | head -n 1 | sed 's/.*If#=\s*\([0-9]*\).*/\1/')
    driver=$(awk '/Quectel/{flag=1} flag; /^$/{flag=0}' /sys/kernel/debug/usb/devices \
        | grep "Driver=" | grep -E "cdc|qmi" | grep -v "option" -m1 \
        | sed -nE 's/.*Driver=([a-zA-Z0-9_+-]+).*/\1/p')
    id="${bus}-${lev}:${prnt}.${port}"
    iface=$(ls "/sys/bus/usb/drivers/$driver/$id/net" 2>/dev/null | head -n 1)
fi

[ -z "$iface" ] && [ -d /sys/class/net/usb0 ]   && iface="usb0"
[ -z "$iface" ] && [ -d /sys/class/net/wwan0 ]  && iface="wwan0"

if [ -n "$iface" ]; then
    if [ "$(uci -q get network.wan.device)" = "$iface" ]; then
        proto=$(uci -q get network.wan.proto)
    fi

    ip=$(ifconfig "$iface"     | grep -i "inet addr" | awk -F ':' '{print $2}' | awk '{print $1}' | head -n 1)
    subnet=$(ifconfig "$iface" | grep -i "mask"      | awk -F ':' '{print $4}' | head -n 1)
    bcast=$(ifconfig "$iface"  | grep -i "bcast"     | awk -F ':' '{print $3}' | awk '{print $1}' | head -n 1)
    hwaddr=$(ifconfig "$iface" | grep -i "hwaddr"    | awk '{print $5}' | head -n 1)
    routeIf=$(ip route | grep -i "default via" | awk '{print $5}')
    if [ "$routeIf" = "$iface" ]; then
        gateway=$(ip route | grep -i "default via" | awk '{print $3}' | head -n 1)
    fi
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

slot_resp=$(at_cmd "AT+QUIMSLOT?" 3)
cur_slot=$(echo "$slot_resp" | grep "+QUIMSLOT:" | awk '{print $2}' | tr -dc '0-9')
[ -z "$cur_slot" ] && {
    slot_resp=$(at_cmd "AT+QDSIM?" 3)
    cur_slot=$(echo "$slot_resp" | grep "+QDSIM:" | awk '{print $2}' | tr -dc '0-9')
    [ -n "$cur_slot" ] && cur_slot=$((cur_slot + 1))
}

if check_internet; then
    status="ready"
else
    status="configuring"
fi

model=$(cat /sys/kernel/debug/usb/devices | awk '/Vendor=2c7c/ {flag=1} flag && /Product=/ {print $0; flag=0}' | awk -F'Product=' '{print $2}' | head -n 1 | tr -d '\r\n ')
[ -z "$model" ] && model="RM500U"

json_output=""
[ -n "$model" ]      && json_output="${json_output},\"model\":\"${model}\""
[ -n "$status" ]     && json_output="${json_output},\"status\":\"${status}\""
[ -n "$operator" ]   && json_output="${json_output},\"operator\":\"${operator}\""
[ -n "$rat" ]        && json_output="${json_output},\"rat\":\"${rat}\""
[ -n "$qeng_rat" ]   && json_output="${json_output},\"ratName\":\"${qeng_rat}\""
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
[ -n "$lte_band" ]   && json_output="${json_output},\"lte_band\":\"${lte_band}\""
[ -n "$rsrp" ]       && json_output="${json_output},\"rsrp\":\"${rsrp}\""
[ -n "$rsrq" ]       && json_output="${json_output},\"rsrq\":\"${rsrq}\""
[ -n "$snr" ]        && json_output="${json_output},\"snr\":\"${snr}\""
[ -n "$sim1_iccid" ] && json_output="${json_output},\"sim1iccid\":\"${sim1_iccid}\""
[ -n "$sim2_iccid" ] && json_output="${json_output},\"sim2iccid\":\"${sim2_iccid}\""
[ -n "$cur_slot" ]   && json_output="${json_output},\"curSlot\":\"${cur_slot}\""

json_output="{$(echo "$json_output" | sed 's/^,//')}"

echo "$json_output" > "$STATUS_FILE"
echo "$json_output"

if [ ! -L "$STATS_LINK" ]; then
    ln -s "$STATUS_FILE" "$STATS_LINK"
fi
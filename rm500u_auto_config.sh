#!/bin/sh

MODEM_DEV="/dev/ttyUSB2"
APN_DB="/www/webUI/db/apn-db.json"
LOG_FILE="/tmp/auto_config.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

at_cmd() {
    local cmd="$1"
    local timeout="${2:-5}"
    local max_retries=3
    local retry=0
    local response=""

    [ -c "$MODEM_DEV" ] || { log "ERROR: $MODEM_DEV not found"; return 1; }

    while [ $retry -lt $max_retries ]; do
        response=$(printf '%s\r\n' "$cmd" | timeout "$timeout" microcom -s 115200 "$MODEM_DEV" 2>/dev/null | tr -d '\r')

        local cleaned=$(echo "$response" | grep -v "^${cmd}$" | grep -v '^$')

        if [ -n "$cleaned" ]; then
            echo "$response"
            return 0
        fi

        retry=$((retry + 1))
        [ $retry -lt $max_retries ] && log "WARN: No response to '$cmd', retrying ($retry/$max_retries)..."
        sleep 1
    done

    log "ERROR: No response to '$cmd' after $max_retries attempts"
    return 1
}

wait_for_sim_ready() {
    local max_wait=30
    local elapsed=0

    while [ $elapsed -lt $max_wait ]; do
        local cpin=$(at_cmd "AT+CPIN?" 3)

        if echo "$cpin" | grep -q "READY"; then
            return 0
        fi

        sleep 2
        elapsed=$((elapsed + 2))
    done

    return 1
}

wait_for_serving_cell() {
    local max_scans=20
    local scan_attempt=0

    log "Waiting for RM500U to find a serving cell..."

    while [ $scan_attempt -lt $max_scans ]; do
        scan_attempt=$((scan_attempt + 1))

        local serving=$(at_cmd 'AT+QENG="servingcell"' 5)

        if echo "$serving" | grep -q '"SEARCH"'; then
            log "Attempt $scan_attempt/$max_scans: Modem is searching for network..."
            sleep 4
            continue
        fi

        # Loose grep validation checking for any of our required connection states
        if echo "$serving" | grep -qE '"LTE"|"NR5G-SA"|"NR5G-NSA"'; then
            # Parse MCC dynamically by checking which index contains the key technology tag
            local mcc=$(echo "$serving" | awk -F',' '
                {
                    for (i=1; i<=NF; i++) {
                        if ($i ~ /"LTE"| "NR5G-SA"| "NR5G-NSA"/) {
                            # MCC is always 2 indices over from the cell technology tag
                            mcc_val = $(i+2);
                            if ($i ~ /"LTE"/) {
                                # For FDD/TDD modes, skip the duplex tag if it exists
                                if ($(i+1) ~ /"FDD"|"TDD"/) { mcc_val = $(i+3); }
                            }
                            gsub(/[^0-9]/, "", mcc_val);
                            if (mcc_val ~ /^[0-9]{3}$/) { print mcc_val; exit }
                        }
                    }
                }
            ')

            if [ -n "$mcc" ]; then
                log "Attempt $scan_attempt/$max_scans: Serving cell found with MCC: $mcc"
                echo "$serving"
                return 0
            fi
        fi

        log "Attempt $scan_attempt/$max_scans: No valid serving cell yet..."
        sleep 3
    done

    log "ERROR: Modem failed to find a network after $max_scans attempts"
    return 1
}

check_internet() {
    local target_iface=$(get_iface)
    [ -n "$target_iface" ] && ping -I "$target_iface" -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 && return 0
    ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1
}

is_pdp_active() {
    local resp=$(at_cmd "AT+CGACT?" 3)
    echo "$resp" | grep -q "+CGACT: 1,1"
}

enable_pdp() {
    at_cmd 'AT+CGACT=1,1' 5
}

disable_data_call() {
    at_cmd 'AT+QNETDEVCTL=0,1,1' 3
}

set_data_call() {
    local retry=0
    local resp=""
    while [ $retry -lt 3 ]; do
        resp=$(at_cmd 'AT+QNETDEVCTL=1,1,1' 5)
        if echo "$resp" | grep -q "OK"; then
            return 0
        fi
        retry=$((retry + 1))
        log "AT+QNETDEVCTL=1,1,1 failed, retrying ($retry/3)..."
        sleep 2
    done
    return 1
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
    log "Restarting network service..."
    /etc/init.d/network restart
    echo '{"status":"success","iface":"'$iface'"}'
}

parse_serving_cell() {
    local serving="$1"

    echo "$serving" | awk -F',' '
        /^\+QENG: "servingcell"/ {
            # Field 3 is RAT for SA mode: "NR5G-SA","TDD",MCC,MNC,...
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
            }
        }
        /^\+QENG: "LTE"/ {
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
            nr_rsrq = $6; gsub(/[^0-9-]/, "", nr_rsrq)
            nr_snr  = $7; gsub(/[^0-9.-]/, "", nr_snr)
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
            print mcc ";" mnc ";" rat ";" band ";" rsrp ";" rsrq ";" snr
        }
    '
}

configure_network() {
    log "Configuring network settings..."

    # Check and set network mode preference to NR5G if not already set
    local pref=$(at_cmd 'AT+QNWPREFCFG="mode_pref"' 3)
    if ! echo "$pref" | grep -q '"mode_pref",NR5G'; then
        log "Setting network mode preference to NR5G..."
        at_cmd 'AT+QNWPREFCFG="mode_pref",NR5G' 5
        sleep 2
    else
        log "Network mode preference is already set to NR5G. Skipping."
    fi

    local serving=$(wait_for_serving_cell)
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to find serving cell"
        return 1
    fi

    log "DEBUG: Raw serving cell output:"
    echo "$serving" | while IFS= read -r line; do log "  $line"; done

    local parsed_info=$(parse_serving_cell "$serving")
    local mcc=$(echo "$parsed_info" | cut -d';' -f1)
    local mnc=$(echo "$parsed_info" | cut -d';' -f2)
    local rat=$(echo "$parsed_info" | cut -d';' -f3)
    local plmn="${mcc}${mnc}"

    log "Detected MCC: $mcc, MNC: $mnc, RAT: $rat, PLMN: $plmn"

    if [ -z "$mcc" ] || [ -z "$mnc" ] || [ "$rat" = "UNKNOWN" ]; then
        log "ERROR: Could not parse valid MCC/MNC/RAT from serving cell"
        return 1
    fi

    local apn=""
    if [ -f "$APN_DB" ]; then
        apn=$(jsonfilter -i "$APN_DB" -e "@[\"$plmn\"].APNs.$rat.apn" 2>/dev/null)

        if [ -z "$apn" ]; then
            log "No APN for RAT: $rat, trying alternatives..."
            for alt_rat in "NR5G" "LTE" "WCDMA" "GSM"; do
                [ "$alt_rat" = "$rat" ] && continue
                apn=$(jsonfilter -i "$APN_DB" -e "@[\"$plmn\"].APNs.$alt_rat.apn" 2>/dev/null)
                if [ -n "$apn" ]; then
                    log "Found APN using RAT: $alt_rat"
                    break
                fi
            done
        fi
    fi

    if [ -z "$apn" ]; then
        apn="internet"
        log "Using default APN: $apn"
    else
        log "Using APN from database: $apn"
    fi

    log "Setting APN: $apn for PLMN: $plmn"
    local cgdcont_resp=$(at_cmd "AT+CGDCONT=1,\"IPV4V6\",\"$apn\"" 5)

    if echo "$cgdcont_resp" | grep -q "OK"; then
        log "APN configured successfully"
    else
        log "WARNING: APN configuration may have failed"
    fi

    at_cmd "AT+QNETDEVCTL=3,1,1" 3 >/dev/null

    setup_iface

    return 0
}

main() {
    log "========================================="
    log "Starting RM500U Auto Configuration"
    log "========================================="

    if [ ! -c "$MODEM_DEV" ]; then
        log "ERROR: Modem device not found: $MODEM_DEV"
        exit 1
    fi

    if configure_network; then
        log "Network configuration completed"
    else
        log "WARNING: Network configuration had issues"
    fi

    log "Verifying internet connection..."
    sleep 10

    if ! check_internet; then
        log "No internet connection detected. Checking PDP status..."
        if ! is_pdp_active; then
            log "PDP Context is not active. Enabling PDP context..."
            enable_pdp
            sleep 2
        fi
        log "Recycling data call..."
        disable_data_call
        sleep 2
        set_data_call
        /etc/init.d/network restart
    fi

    log "========================================="
    log "RM500U Auto Configuration Complete"

    if [ -f /tmp/modem_iccid_1 ]; then
        log "Slot 1: $(cat /tmp/modem_iccid_1)"
    fi
    if [ -f /tmp/modem_iccid_2 ]; then
        log "Slot 2: $(cat /tmp/modem_iccid_2)"
    fi

    log "========================================="
}

main
exit 0
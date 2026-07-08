#!/bin/sh

echo "Content-Type: application/json"
echo ""

read INPUT

type=$(echo "$INPUT"  | grep -o 'type=[^&]*'  | cut -d= -f2 | sed 's/%22//g' | tr -d '\r\n ')
bands=$(echo "$INPUT" | grep -o 'bands=[^&]*' | cut -d= -f2 | sed 's/%3A/:/g' | tr -d '\r\n ')

STATS_FILE="/tmp/lte_stats"
MODEM_DEV="/dev/ttyUSB2"
LOG_FILE="/tmp/rm500u_set_band.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

at_cmd() {
    local cmd="$1"
    local timeout="${2:-5}"

    touch /tmp/modem.lock
    exec 8>/tmp/modem.lock
    flock -x 8

    local resp
    resp=$(printf '%s\r\n' "$cmd" | microcom -t $((timeout * 1000)) "$MODEM_DEV" 2>/dev/null | tr -d '\r')

    flock -u 8
    exec 8>&-
    echo "$resp"
}

log "=== Band lock request ==="
log "Raw INPUT: $INPUT"
log "Parsed type: $type"
log "Parsed bands: $bands"

if [ -z "$type" ] || [ -z "$bands" ]; then
    log "ERROR: Missing type or bands"
    echo "{\"status\":\"error\", \"message\":\"Invalid input. Type:[$type] Bands:[$bands]\"}"
    exit 1
fi

AT_CMD="AT+QNWPREFCFG=\"${type}\",${bands}"
log "Sending AT command: $AT_CMD"
resp=$(at_cmd "$AT_CMD" 5)
log "AT response: $resp"

if echo "$resp" | grep -q "OK"; then
    log "Band lock OK, waiting for modem to settle..."
    sleep 2

    actual_info=$(at_cmd "AT+QENG=\"servingcell\"" 5)
    log "Serving cell response: $actual_info"

    case "$type" in
        lte_band)
            active_band=$(echo "$actual_info" | grep '+QENG: "LTE"' | awk -F',' '{print $8}' | tr -dc '0-9')
            ;;
        nsa_nr5g_band)
            active_band=$(echo "$actual_info" | grep '+QENG: "NR5G-NSA"' | awk -F',' '{print $9}' | tr -dc '0-9')
            ;;
        nr5g_band)
            active_band=$(echo "$actual_info" | grep '+QENG: "servingcell"' | awk -F',' '{print $11}' | tr -dc '0-9')
            ;;
    esac

    log "Extracted active_band: $active_band"
    [ -z "$active_band" ] && active_band="$bands" && log "active_band empty, falling back to requested bands: $bands"

    if [ -f "$STATS_FILE" ]; then
        case "$type" in
            lte_band)
                sed -i "s/\"lte_band\":\"[^\"]*\"/\"lte_band\":\"$active_band\"/" "$STATS_FILE"
                ;;
            nsa_nr5g_band|nr5g_band)
                sed -i "s/\"band\":\"[^\"]*\"/\"band\":\"$active_band\"/" "$STATS_FILE"
                ;;
        esac
        log "Updated STATS_FILE with active_band: $active_band"
    else
        log "WARN: STATS_FILE not found at $STATS_FILE"
    fi

    log "Success: band lock applied, active=$active_band"
    echo "{\"status\":\"success\", \"active\":\"$active_band\", \"message\":\"Band mask updated.\"}"
else
    err_detail=$(echo "$resp" | tr -d '\r\n' | sed 's/"/\\"/g')
    log "ERROR: Modem rejected command. Response: $resp"
    echo "{\"status\":\"error\", \"message\":\"Modem Rejected: $err_detail\"}"
fi

/www/webUI/cgi-bin/rm500u_get_lte_stats.sh >> $LOG_FILE 2>&1
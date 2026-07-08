#!/bin/sh

echo "Content-Type: application/json"
echo ""

read INPUT

parse_query() {
    local input="$1"
    local key="$2"
    echo "$input" | grep -o "$key=[^&]*" | cut -d= -f2 | sed 's/%3A/:/g' | tr -d '\r\n '
}

MODEM_DEV="/dev/ttyUSB2"
LOG_FILE="/tmp/band_lock.log"
STATS_FILE="/tmp/lte_stats"

# Ensure log file exists
touch "$LOG_FILE" 2>/dev/null || true

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${1:-INFO}] $2" | tee -a "$LOG_FILE" >&2
}

calculate_mask() {
    local bands="$1"
    local min_band="$2"
    local max_band="$3"
    
    [ -z "$bands" ] || [ "$bands" = "0" ] && { echo "0000000000000000"; return 0; }
    [ "$bands" = "all" ] && { echo "FFFFFFFFFFFFFFFF"; return 0; }

    echo "$bands" | awk -v min_b="$min_band" -v max_b="$max_band" -F':' '
    BEGIN {
        split("1 2 4 8", p, " ")
        # Initialize 16 hex nibbles (64 bits)
        for(i=0; i<16; i++) bits[i] = 0
    }
    {
        for (i=1; i<=NF; i++) {
            b = $i; gsub(/^[ \t]+|[ \t]+$/, "", b)
            if (length(b) > 0 && b+0 >= min_b+0 && b+0 <= max_b+0) {
                rel_bit = int(b) - int(min_b)
                # Find which 4-bit nibble this bit falls into
                nibble_idx = int(rel_bit / 4)
                bit_in_nibble = rel_bit % 4
                bits[nibble_idx] += p[bit_in_nibble + 1]
            }
        }
    }
    END {
        res = ""
        # Build hex string from highest nibble to lowest
        for(i=15; i>=0; i--) {
            res = res sprintf("%X", bits[i])
        }
        # Always output a fixed 16-digit mask
        if (res == "") res = "0000000000000000"
        while (length(res) < 16) res = "0" res
        print res
    }'
}

at_cmd() {
    local cmd="$1"
    local timeout="${2:-10}"
    local response=""

    # Use lock to prevent collision with background stats scripts
    touch /tmp/modem.lock
    exec 8>/tmp/modem.lock
    
    # BusyBox flock v1.35.0 often lacks the -w (wait) option.
    # We implement a retry loop with -n (non-blocking) to simulate a 15-second timeout.
    local i=0
    local locked=0
    while [ $i -lt 15 ]; do
        if flock -x -n 8; then
            locked=1
            break
        fi
        sleep 1
        i=$((i + 1))
    done

    if [ "$locked" -eq 1 ]; then
        local ms=$((timeout * 1000))
        response=$(printf '%s\r' "$cmd" | microcom -t "$ms" "$MODEM_DEV" 2>/dev/null | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        flock -u 8
    else
        log "WARN" "Could not acquire modem lock after 15 seconds for command: $cmd"
    fi

    exec 8>&-
    echo "$response"
}

req_type=$(parse_query "$INPUT" "type")
curr_rat=""
[ -f "$STATS_FILE" ] && curr_rat=$(jsonfilter -i "$STATS_FILE" -e '@.rat' 2>/dev/null)

# Determine acquisition order based on current RAT from stats file
case "$curr_rat" in
    7)      acq="03" ;;
    11)     acq="0403" ;;
    13)     acq="0304" ;;
    *)      acq="00" ;;
esac

if [ -z "$req_type" ]; then
    case "$curr_rat" in
        7)      req_type="lte_band" ;;
        11)     req_type="nr5g_band" ;;
        13)     req_type="both" ;;
        *)      req_type="default" ;;
    esac
fi

log "INFO" "Context - RAT: [$curr_rat], ACQ: [$acq], ReqType: [$req_type]"

lte_raw=$(parse_query "$INPUT" "lte_bands")
[ -z "$lte_raw" ] && lte_raw=$(parse_query "$INPUT" "bands")

nr_raw=$(parse_query "$INPUT" "nr5g_bands")
[ -z "$nr_raw" ] && { [ "$req_type" = "nr5g_band" ] || [ "$req_type" = "both" ]; } && nr_raw=$(parse_query "$INPUT" "bands")

# Ensure parameters are mutually exclusive based on request type
[ "$req_type" = "lte_band" ] && nr_raw=""
[ "$req_type" = "nr5g_band" ] && lte_raw=""

if [ -z "$INPUT" ] || [ -z "$req_type" ]; then
    echo '{"status":"error","message":"No input or invalid type provided"}'
    exit 1
fi

log "INFO" "===== SRM810 Band Lock Request ====="
log "INFO" "Raw Input: $INPUT"
log "DEBUG" "Parsed - Type: $req_type, LTE: $lte_raw, NR5G: $nr_raw"

    # Validate request type
    case "$req_type" in
        lte_band|nr5g_band|both|default)
            ;; # Valid
        *)
            log "ERROR" "Invalid request type: $req_type"
            echo '{"status":"error","message":"Invalid type. Use: lte_band, nr5g_band, both, or default"}'
            exit 1 # Use exit instead of return as it's no longer in a function
            ;;
    esac
    
    # Initialize band parameters
    lte_1_64="0"
    lte_65_128="0"
    nr_1_64="0"
    nr_65_128="0"
    
    # Process based on type
    if [ "$req_type" = "default" ]; then
        lte_1_64="FFFFFFFFFFFFFFFF"
        lte_65_128="FFFFFFFFFFFFFFFF"
        nr_1_64="FFFFFFFFFFFFFFFF"
        nr_65_128="FFFFFFFFFFFFFFFF"
    fi

    # Calculate masks (skipped if default was handled above)
    if [ "$req_type" != "default" ]; then
        lte_1_64=$(calculate_mask "$lte_raw" 1 64)
        lte_65_128=$(calculate_mask "$lte_raw" 65 128)
        nr_1_64=$(calculate_mask "$nr_raw" 1 64)
        nr_65_128=$(calculate_mask "$nr_raw" 65 128)

        # Ensure blank values never make it into the AT command as empty fields
        lte_1_64=${lte_1_64:-0000000000000000}
        lte_65_128=${lte_65_128:-0000000000000000}
        nr_1_64=${nr_1_64:-0000000000000000}
        nr_65_128=${nr_65_128:-0000000000000000}

        log "DEBUG" "LTE Masks - Bands 1-64: 0x$lte_1_64, Bands 65-128: 0x$lte_65_128"
        log "DEBUG" "NR5G Masks - Bands 1-64: 0x$nr_1_64, Bands 65-128: 0x$nr_65_128"
    fi
    
    # Build AT command
    # For SRM810, the last parameter is expected to be 0, and the NR_EXT mask must be passed as a full 16-digit value.
    at_command="AT^SYSCFGEX=\"$acq\",2000004400000,0,2,$lte_1_64,$lte_65_128,$nr_1_64,\"$nr_65_128\",0"
    
    log "INFO" "Sending command: $at_command"
    
    # Execute AT command with generous 10-second window for chatty modem
    resp=$(at_cmd "$at_command" 10)
    log "DEBUG" "Response: $resp"
    
    # Check for success
    if echo "$resp" | grep -q "OK"; then
        log "INFO" "Band lock applied. Initializing modem reset (AT+CFUN=0 then AT+CFUN=1)..."
        # Execute cycle to apply band change
        _=$(at_cmd "AT+CFUN=0" 5)
        sleep 2
        _=$(at_cmd "AT+CFUN=1" 5)

        log "INFO" "Band lock reset triggered. Monitoring handed over to frontend."
        echo "{\"status\":\"success\", \"active\":\"Applied\", \"message\":\"Band lock applied. Modem is re-initializing.\"}"
    else
        # Check for specific error
        error_detail=$(echo "$resp" | tr '\n' ' ' | sed 's/"/\\"/g')
        
        if echo "$resp" | grep -qi "ERROR\|CME"; then
            log "ERROR" "Modem rejected command: $error_detail"
            error_detail="Modem error"
        else
            log "ERROR" "Unexpected response: $error_detail"
            error_detail="No OK response"
        fi
        
        log "ERROR" "Modem Rejected: $error_detail"
        echo "{\"status\":\"error\", \"message\":\"Modem Rejected: $error_detail\"}"
    fi
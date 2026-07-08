#!/bin/sh
echo "Content-Type: text/plain"
echo ""

LOG_FILE="/tmp/band_sync.log"
STATS_FILE="/tmp/lte_stats"
OUT_FILE="/tmp/supported_bands"
MODEM_DEV="/dev/ttyUSB2"

# Logging function
log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_msg "--- Sync Started ---"

# 1. Check Stats File
if [ ! -f "$STATS_FILE" ]; then
    log_msg "ERROR: $STATS_FILE not found."
    exit 1
fi

# 2. Extract RAT
raw_stats=$(cat "$STATS_FILE")
rat=$(echo "$raw_stats" | /usr/bin/jsonfilter -e '@.rat' | tr -d '[:space:]')
log_msg "Found RAT: [$rat]"

# 3. Determine Command
if [ "$rat" = "11" ]; then
    cmd='AT+QNWPREFCFG="nr5g_band"'
    pattern="nr5g_band"
    prefix="N"
elif [ "$rat" = "7" ]; then
    cmd='AT+QNWPREFCFG="lte_band"'
    pattern="lte_band"
    prefix="B"
else
    log_msg "WARNING: RAT is [$rat], defaulting to LTE."
    cmd='AT+QNWPREFCFG="lte_band"'
    pattern="lte_band"
    prefix="B"
fi

# 4. Query Modem
log_msg "Sending: $cmd"
resp=$(echo -e "$cmd\r" | microcom -t 2000 "$MODEM_DEV" 2>/dev/null)

# 5. Parse Response
supported=$(echo "$resp" | grep "$pattern" | awk -F',' '{print $2}' | tr -d '"\r\n ')

if [ -n "$supported" ]; then
    echo "${prefix}:${supported}" > "$OUT_FILE"
    log_msg "SUCCESS: Written [${prefix}:${supported}] to $OUT_FILE"
else
    log_msg "ERROR: Modem response was empty or invalid. Raw: $resp"
fi

log_msg "--- Sync Finished ---"
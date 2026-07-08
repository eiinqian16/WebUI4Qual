#!/bin/sh

MODEM_DEV="/dev/ttyUSB2"

# Clean AT command function
at_cmd() {
    local cmd="$1"
    local timeout="${2:-5}"
    local response=""
    
    if [ ! -c "$MODEM_DEV" ]; then
        echo "ERROR: Modem device $MODEM_DEV not found or not a character device." >&2
        return 1
    fi
    
    exec 3<> "$MODEM_DEV" 2>/dev/null || return 1
    printf "%s\r\n" "$cmd" >&3
    response=$(timeout "$timeout" cat <&3 2>/dev/null | tr -d '\r')
    exec 3>&-
    
    echo "$response"
    return 0
}

echo "=== Modem Diagnostics ==="
cfun=$(at_cmd 'AT+CFUN?' 3)
cpin=$(at_cmd 'AT+CPIN?' 3)
echo "CFUN Status (Radio):"
echo "$cfun"
echo "CPIN Status (SIM):"
echo "$cpin"
echo "========================="
echo ""

echo "Querying servingcell from modem at $MODEM_DEV (retrying if busy)..."
serving=""
attempts=0
max_attempts=10

while [ $attempts -lt $max_attempts ]; do
    attempts=$((attempts + 1))
    serving=$(at_cmd 'AT+QENG="servingcell"' 5)
    
    # If we get a valid servingcell response or search response, break
    if echo "$serving" | grep -qE '"servingcell"|"SEARCH"'; then
        break
    fi
    
    echo "Attempt $attempts/$max_attempts: Serving cell info not ready (got: $(echo "$serving" | tr -d '\n\r')). Retrying in 3 seconds..."
    sleep 3
done

if [ -z "$serving" ] || echo "$serving" | grep -q "ERROR"; then
    echo ""
    echo "ERROR: Failed to retrieve serving cell info. Response was:"
    echo "$serving"
    echo "Tip: Check if the SIM card is inserted and if the radio is enabled (AT+CFUN=1)."
    exit 1
fi

echo ""
echo "=== Raw Modem Response ==="
echo "$serving"
echo "=========================="
echo ""

# Wait for serving cell logic simulation
wait_mcc=$(echo "$serving" | awk -F ',' '
    $1 ~ /"servingcell"/ && NF >= 6 && $5 ~ /^[0-9]+$/ { print $5; exit }
    $1 ~ /"LTE"/ && NF >= 4 && $3 ~ /^[0-9]+$/ { print $3; exit }
' | tr -d '\n\r ')

# Extract network info logic simulation
parsed_info=$(echo "$serving" | awk -F ',' '
    $1 ~ /"servingcell"/ && NF >= 6 && $5 ~ /^[0-9]+$/ {
        mcc = $5
        mnc = $6
        rat = $3
        gsub(/"/, "", rat)
    }
    $1 ~ /"LTE"/ && NF >= 4 && $3 ~ /^[0-9]+$/ {
        lte_mcc = $3
        lte_mnc = $4
    }
    $1 ~ /"NR5G-NSA"/ {
        nsa = 1
    }
    END {
        if (!mcc && lte_mcc) {
            mcc = lte_mcc
            mnc = lte_mnc
        }
        if (nsa) {
            rat = "NR5G-NSA"
        } else if (!rat && lte_mcc) {
            rat = "LTE"
        }
        print mcc ";" mnc ";" rat
    }
')

mcc=$(echo "$parsed_info" | cut -d ';' -f 1 | tr -d ' \n\r')
mnc=$(echo "$parsed_info" | cut -d ';' -f 2 | tr -d ' \n\r')
rat=$(echo "$parsed_info" | cut -d ';' -f 3 | tr -d ' \n\r')

echo "=== Parsed Results ==="
echo "Wait MCC check output: '$wait_mcc'"
echo "Extracted MCC:          '$mcc'"
echo "Extracted MNC:          '$mnc'"
echo "Extracted RAT:          '$rat'"
echo "======================"

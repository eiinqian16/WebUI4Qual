#!/bin/sh

# Redirect all debug output to stderr from the start
exec 2>/tmp/network_scan.log

echo "Content-Type: application/json"
echo ""

pgrep -f "monitor_sim.sh" | xargs -r kill
pgrep -f "cat /dev/ttyUSB2" | xargs -r kill
sleep 1

MODEM_PORT="/dev/ttyUSB2"

# Function to get available networks
get_available_networks() {
    tmpfile=$(mktemp)
    {
        echo -e "AT+COPS=?\r"
        sleep 15
    } | microcom -t 20000 "$MODEM_PORT" > "$tmpfile" 2>&1 &
    wait
    cat "$tmpfile"
    rm -f "$tmpfile"
}

# Function to get signal quality
get_signal_quality() {
    tmpfile=$(mktemp)
    {
        echo -e 'AT+QENG="servingcell"\r'
        sleep 3
    } | microcom -t 5000 "$MODEM_PORT" > "$tmpfile" 2>&1 &
    wait
    cat "$tmpfile"
    rm -f "$tmpfile"
}

# Function to calculate signal score (lower is better)
calculate_signal_score() {
    local rsrp=$1
    local rsrq=$2
    local rat=$3
    
    # Normalize RSRP and RSRQ to 0-100 scale where 0 is best
    if [ "$rat" = "LTE" ]; then
        # LTE RSRP: -44 (best) to -140 (worst) -> normalize to 0-100
        rsrp_score=$(echo "scale=2; (($rsrp + 44) / (-140 + 44)) * 100" | bc)
        # LTE RSRQ: -3 (best) to -20.5 (worst) -> normalize to 0-100
        rsrq_score=$(echo "scale=2; (($rsrq + 3) / (-20.5 + 3)) * 100" | bc)
    elif [ "$rat" = "NR5G-SA" ] || [ "$rat" = "NR5G" ]; then
        # 5G RSRP: -31 (best) to -156 (worst) -> normalize to 0-100
        rsrp_score=$(echo "scale=2; (($rsrp + 31) / (-156 + 31)) * 100" | bc)
        # 5G RSRQ: 20 (best) to -43 (worst) -> normalize to 0-100
        rsrq_score=$(echo "scale=2; ((20 - $rsrq) / (20 + 43)) * 100" | bc)
    else
        echo "999"
        return
    fi
    
    # Combined score (average of both)
    combined=$(echo "scale=2; ($rsrp_score + $rsrq_score) / 2" | bc)
    echo "$combined"
}

# Main function
check_networks() {
    echo "=== Network Scan Started at $(date) ===" >&2
    echo "Getting available networks..." >&2
    response=$(get_available_networks)
    
    # Create temporary files
    network_file=$(mktemp)
    results_file=$(mktemp)
    
    # Extract available networks (status 1=available, 2=currently registered)
    echo "$response" | awk -F'[()]' '{
        for(i=2;i<=NF;i++) {
            if($i ~ /^[12],/) {
                gsub(/"/, "", $i)
                split($i, a, ",")
                if(a[2] != "" && a[4] != "") {
                    print a[2] "|" a[4]
                }
            }
        }
    }' | sort -u > "$network_file"
    
    network_count=$(wc -l < "$network_file")
    echo "Found $network_count networks to test" >&2
    
    if [ "$network_count" -eq 0 ]; then
        rm -f "$network_file" "$results_file"
        echo '{"error": "No available networks found"}'
        return
    fi
    
    # Test each network
    while IFS='|' read -r operator_name mccmnc; do
        if [ -z "$operator_name" ] || [ -z "$mccmnc" ]; then
            continue
        fi
        
        echo "Testing: $operator_name ($mccmnc)" >&2
        
        # Deregister first
        echo -e "AT+COPS=2\r" | microcom -t 5000 "$MODEM_PORT" > /dev/null 2>&1
        sleep 2
        
        # Register to network
        echo -e "AT+COPS=1,2,\"$mccmnc\"\r" | microcom -t 10000 "$MODEM_PORT" > /dev/null 2>&1
        sleep 5
        
        # Get signal quality
        signal_data=$(get_signal_quality)
        
        # Parse QENG response
        qeng_line=$(echo "$signal_data" | grep '+QENG:' | grep 'servingcell')
        
        if [ -z "$qeng_line" ]; then
            echo "  No servingcell data" >&2
            continue
        fi
        
        # Remove the +QENG: "servingcell", prefix
        data=$(echo "$qeng_line" | sed 's/^+QENG: *"servingcell" *,//' | tr -d '\r')
        
        # Parse fields (handle both with and without quotes around state)
        state=$(echo "$data" | cut -d',' -f1 | tr -d '"' | sed 's/^ *//;s/ *$//')
        rat=$(echo "$data" | cut -d',' -f2 | tr -d '"' | sed 's/^ *//;s/ *$//')
        
        # Get RSRP and RSRQ - they're at fixed positions
        # LTE: state,rat,is_tdd,mcc,mnc,cellid,pcid,earfcn,freq_band,ul_bw,dl_bw,tac,rsrp,rsrq,...
        rsrp=$(echo "$data" | cut -d',' -f13 | sed 's/^ *//;s/ *$//')
        rsrq=$(echo "$data" | cut -d',' -f14 | sed 's/^ *//;s/ *$//')
        
        echo "  State: $state, RAT: $rat, RSRP: $rsrp, RSRQ: $rsrq" >&2
        
        # Only accept NOCONN state (network is attachable)
        if [ "$state" != "NOCONN" ]; then
            echo "  Skipping (state is $state, need NOCONN)" >&2
            continue
        fi
        
        # Validate RSRP and RSRQ are numeric
        if ! echo "$rsrp" | grep -qE '^-?[0-9]+\.?[0-9]*$' || ! echo "$rsrq" | grep -qE '^-?[0-9]+\.?[0-9]*$'; then
            echo "  Invalid RSRP/RSRQ values" >&2
            continue
        fi
        
        # Calculate signal score
        score=$(calculate_signal_score "$rsrp" "$rsrq" "$rat")
        
        if [ "$score" = "999" ]; then
            echo "  Unknown RAT: $rat" >&2
            continue
        fi
        
        echo "  Signal score: $score" >&2
        
        # Store result: score|operator|mccmnc|state|rat|rsrp|rsrq
        echo "$score|$operator_name|$mccmnc|$state|$rat|$rsrp|$rsrq" >> "$results_file"
        
    done < "$network_file"
    
    # Deregister after testing
    echo -e "AT+COPS=2\r" | microcom -t 5000 "$MODEM_PORT" > /dev/null 2>&1
    
    # Clean up network file
    rm -f "$network_file"
    
    # Find best network (lowest score)
    if [ ! -s "$results_file" ]; then
        rm -f "$results_file"
        echo '{"error": "No networks with NOCONN state found"}'
        return
    fi
    
    best=$(sort -t'|' -k1 -n "$results_file" | head -n1)
    rm -f "$results_file"
    
    # Parse best result
    score=$(echo "$best" | cut -d'|' -f1)
    operator=$(echo "$best" | cut -d'|' -f2)
    mccmnc=$(echo "$best" | cut -d'|' -f3)
    state=$(echo "$best" | cut -d'|' -f4)
    rat=$(echo "$best" | cut -d'|' -f5)
    rsrp=$(echo "$best" | cut -d'|' -f6)
    rsrq=$(echo "$best" | cut -d'|' -f7)
    
    # Output JSON
    cat <<EOF
{
  "operator": "$operator",
  "mccmnc": "$mccmnc",
  "state": "$state",
  "rat": "$rat",
  "rsrp": $rsrp,
  "rsrq": $rsrq,
  "signal_score": $score
}
EOF
}

check_networks

/usr/bin/monitor_sim.sh &
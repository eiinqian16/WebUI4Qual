#!/bin/sh
echo "Content-Type: application/json"
echo ""

DEVICE=$(echo "$QUERY_STRING" | sed -n 's/^.*device=\([^&]*\).*$/\1/p')
#DEVICE="radio0"

get_phy_from_radio() {
    local radio=$1
    local index=${radio#radio}
    echo "phy$index"
}

get_iface_for_radio() {
    local radio=$1
    local phy_index=${radio#radio}
    iw dev | awk -v p="$phy_index" '
        /phy#/ {phy=$1; sub("phy#","",phy)}
        /Interface/ {iface=$2; if(phy==p) {print iface; exit}}
    '
}

get_current_freq() {
    local device=$1
    dev=$(get_iface_for_radio $device)
    iw dev "$dev" info 2>/dev/null | awk '/channel/ {print $3; exit}' | awk -F '(' '{print $2; exit}'
}

get_current_band() {
    local freq_mhz=$(get_current_freq $1)
    if [ "$freq_mhz" -ge 2412 ] && [ "$freq_mhz" -le 2484 ]; then
        echo "2.4GHz"
    elif [ "$freq_mhz" -ge 5180 ] && [ "$freq_mhz" -le 5885 ]; then
        echo "5GHz"
    elif [ "$freq_mhz" -ge 5955 ] && [ "$freq_mhz" -le 7115 ]; then
        echo "6GHz"
    else
        echo "Unknown"
    fi
}

phy=$(get_phy_from_radio $DEVICE)
GET_BAND=$(get_current_band $DEVICE)

if [ -z "$DEVICE" ]; then
    echo '{"error": "No device provided"}'
    exit 1
fi

if [ -z "$GET_BAND" ]; then
    echo "{\"error\": \"Band of $DEVICE not found\"}"
    exit 1 
fi

IS_2G=0
IS_5G6G=0
if [ -n "$GET_BAND" ]; then
    BAND_INFO=$(echo "$GET_BAND")
    if echo "$BAND_INFO" | grep -q "2.4GHz"; then
        IS_2G=1
        GET_HWMODES="IEEE802.11bgnax"
    fi
    if echo "$BAND_INFO" | grep -q "5GHz\|6GHz"; then
        IS_5G6G=1 
        GET_HWMODES="IEEE802.11nacax"
    fi
fi

if [ -z "$GET_HWMODES" ]; then
    echo "{\"error\": \"Device $DEVICE not found\"}"
    exit 1
fi

# Build HW modes array
MODES_JSON="["
add_comma=0
for m in b g n a ac ax be; do
    if echo "$GET_HWMODES" | grep -qi "$m"; then
        [ $add_comma -eq 1 ] && MODES_JSON="${MODES_JSON}, "
        MODES_JSON="${MODES_JSON}\"11$m\""
        add_comma=1
    fi
done
MODES_JSON="${MODES_JSON}]"

# Build HT modes mapping
HT_MODES_JSON="{"
add_comma=0

if echo "$GET_HWMODES" | grep -qi "b\|g\|a"; then
    # Legacy modes - no HT modes
    for m in b g a; do
        if echo "$GET_HWMODES" | grep -qi "$m"; then
            [ $add_comma -eq 1 ] && HT_MODES_JSON="${HT_MODES_JSON}, "
            HT_MODES_JSON="${HT_MODES_JSON}\"11$m\": []"
            add_comma=1
        fi
    done
fi

if echo "$GET_HWMODES" | grep -qi "n"; then
    [ $add_comma -eq 1 ] && HT_MODES_JSON="${HT_MODES_JSON}, "
    HT_MODES_JSON="${HT_MODES_JSON}\"11n\": [\"HT20\", \"HT40\"]"
    add_comma=1
fi

if echo "$GET_HWMODES" | grep -qi "ac"; then
    [ $add_comma -eq 1 ] && HT_MODES_JSON="${HT_MODES_JSON}, "
    HT_MODES_JSON="${HT_MODES_JSON}\"11ac\": [\"VHT20\", \"VHT40\", \"VHT80\", \"VHT160\"]"
    add_comma=1
fi

if echo "$GET_HWMODES" | grep -qi "ax\|be"; then
    if [ "$IS_2G" -eq 1 ]; then
        [ $add_comma -eq 1 ] && HT_MODES_JSON="${HT_MODES_JSON}, "
        HT_MODES_JSON="${HT_MODES_JSON}\"11ax\": [\"HE20\", \"HE40\"]"
        add_comma=1
        HT_MODES_JSON="${HT_MODES_JSON}, \"11be\": [\"EHT20\", \"EHT40\"]"
    elif [ "$IS_5G6G" -eq 1 ]; then
        [ $add_comma -eq 1 ] && HT_MODES_JSON="${HT_MODES_JSON}, "
        HT_MODES_JSON="${HT_MODES_JSON}\"11ax\": [\"HE20\", \"HE40\", \"HE80\", \"HE160\"]"
        add_comma=1
        HT_MODES_JSON="${HT_MODES_JSON}, \"11be\": [\"EHT20\", \"EHT40\", \"EHT80\", \"EHT160\"]"
    fi
fi

HT_MODES_JSON="${HT_MODES_JSON}}"

# Output JSON
cat <<EOF
{
  "device": "$DEVICE",
  "phy": "$phy",
  "band": "$BAND_INFO",
  "hw_modes": $MODES_JSON,
  "ht_modes": $HT_MODES_JSON
}
EOF
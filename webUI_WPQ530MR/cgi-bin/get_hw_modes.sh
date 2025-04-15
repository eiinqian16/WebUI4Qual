#!/bin/sh
echo "Content-Type: application/json"
echo ""

DEVICE=$(echo "$QUERY_STRING" | sed -n 's/^.*device=\([^&]*\).*$/\1/p')

HW_MODES_PATH="/sys/class/net/$DEVICE/hwmodes"
BAND_PATH="/sys/class/net/$DEVICE/supported_bands"

if [ -z "$DEVICE" ]; then
    echo '{"error": "No device provided"}'
    exit 1
fi

if [ ! -f "$HW_MODES_PATH" ]; then
    echo "{\"error\": \"Device $DEVICE not found\"}"
    exit 1
fi

IS_2G=0
IS_5G6G=0
if [ -f "$BAND_PATH" ]; then
    BAND_INFO=$(cat "$BAND_PATH")
    if echo "$BAND_INFO" | grep -q "2GHz"; then
        IS_2G=1
    fi
    if echo "$BAND_INFO" | grep -q "5GHz\|6GHz"; then
        IS_5G6G=1 
    fi
fi

HW_MODES=$(cat "$HW_MODES_PATH")

echo "{"
echo '  "hw_modes": {'

SEEN_HW=""
FIRST_HW=1

for MODE in $HW_MODES; do
    if echo "$MODE" | grep -q '^11B$'; then
        HW="11b"
        HT=""
    elif echo "$MODE" | grep -q '^11G$'; then
        HW="11g"
        HT=""
    elif echo "$MODE" | grep -q '^11A$'; then
        HW="11a"
        HT=""
    elif echo "$MODE" | grep -q '^11NA_HT'; then
        HW="11na"
        HT=$(echo "$MODE" | sed -E 's/.*HT([0-9]+).*/HT\1/')
    elif echo "$MODE" | grep -q '^11AC_VHT'; then
        HW="11ac"
        HT=$(echo "$MODE" | sed -E 's/.*VHT([0-9]+).*/VHT\1/')
    elif echo "$MODE" | grep -q '^11AXG_HE'; then
        HW="11axg"
        HT=$(echo "$MODE" | sed -E 's/.*HE([0-9]+).*/HE\1/')
    elif echo "$MODE" | grep -q '^11AXA_HE'; then
        HW="11axa"
        HT=$(echo "$MODE" | sed -E 's/.*HE([0-9]+).*/HE\1/')
    elif echo "$MODE" | grep -q '^11BEG_EHT'; then
        HW="11beg"
        HT=$(echo "$MODE" | sed -E 's/.*EHT([0-9]+).*/EHT\1/')
    elif echo "$MODE" | grep -q '^11BEA_EHT'; then
        HW="11bea"
        HT=$(echo "$MODE" | sed -E 's/.*EHT([0-9]+).*/EHT\1/')
    else
        continue
    fi

    if [ "$IS_2G" -eq 1 ] && [ "$HW" = "11axa" ]; then
        continue
    fi

    if [ "$IS_5G6G" -eq 1 ] && [ "$HW" = "11axg" ]; then
        continue
    fi

    if ! echo "$SEEN_HW" | grep -wq "$HW"; then
        if [ $FIRST_HW -eq 0 ]; then
            echo "    ],"
        fi
        FIRST_HW=0
        echo "    \"$HW\": ["
        SEEN_HW="$SEEN_HW $HW"
        SEEN_HT=""
        FIRST_HT=1
    fi

    if [ -n "$HT" ] && ! echo "$SEEN_HT" | grep -wq "$HT"; then
        if [ $FIRST_HT -eq 0 ]; then
            echo ","
        fi
        FIRST_HT=0
        SEEN_HT="$SEEN_HT $HT"
        echo -n "        \"$HT\""
    fi
done

echo "    ]"
echo "  }"
echo "}"


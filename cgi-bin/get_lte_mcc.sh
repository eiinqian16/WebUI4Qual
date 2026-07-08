#!/bin/sh

echo "Content-Type: application/json"
echo ""

MODEM_DEV="/dev/ttyUSB2"

[ -z "$MODEM_DEV" ] && { echo '{"error":"No modem found"}'; exit 1; }

# Create response file
touch /tmp/qeng_resp.txt

# Read from modem with timeout
timeout 5 cat "$MODEM_DEV" > /tmp/qeng_resp.txt &
CAT_PID=$!

sleep 1

# Send command
echo -e 'AT+QENG="servingcell"\r' > "$MODEM_DEV"

# Wait for response
sleep 2

# Kill cat process
kill $CAT_PID 2>/dev/null
wait $CAT_PID 2>/dev/null

# Read and clean response
resp=$(cat /tmp/qeng_resp.txt | tr -d '\r')
rm -f /tmp/qeng_resp.txt

if [ -z "$resp" ]; then
    echo '{"error":"No serving cell detected"}'
    exit 1
fi

# Extract and clean values - remove all non-numeric characters except commas
mcc=$(echo "$resp" | grep -i "+qeng" | awk -F ',' '{print $5}' | tr -cd '0-9')
mnc=$(echo "$resp" | grep -i "+qeng" | awk -F ',' '{print $6}' | tr -cd '0-9')

if [ -n "$mcc" ] && [ -n "$mnc" ]; then
    echo "{\"mcc\":\"${mcc}\",\"mnc\":\"${mnc}\"}"
else
    echo '{"error":"Could not extract MCC/MNC"}'
fi
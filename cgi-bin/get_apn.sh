#!/bin/sh

echo "Content-Type: application/json"
echo ""

MODEM_DEV="/dev/ttyUSB2"

[ -z "$MODEM_DEV" ] && { echo '{"error":"No modem found"}'; exit 1; }

echo -e "AT+COPS=?\r\n" > "$MODEM_DEV"
apnList=$(timeout 5 cat "$MODEM_DEV" 2>/dev/null || true)

# check if response detected
if [ -z "$apnList" ]; then
    echo '{"error": "No response from modem"}'
    exit 1
fi

echo "$apnList" | grep -oE '\([^)]*\)' | awk '
BEGIN {
    print "["
    first = 1
}
{
    gsub(/[\(\)]/, "", $0)
    n = split($0, f, ",")

    if (n >= 5 && f[2] ~ /^"/) {
        gsub(/"/, "", f[2])
        gsub(/"/, "", f[3])
        gsub(/"/, "", f[4])
        if (!first) print " },"
        first = 0
        print " {"
        printf "  \"name\": \"%s\",\n", f[2]
        printf "  \"short_name\": \"%s\",\n", f[3]
        printf "  \"mccmnc\": \"%s\",\n", f[4]
        printf "  \"rat\": \"%s\"\n", f[5]
    }
}
END {
    if (!first) print " }"
    print "]"
}'
#!/bin/sh

# Set content type to json
echo "Content-Type: application/json"
echo ""  # Separate header from body

client_data=$(awk '/duid/ {exit} {print}' /tmp/dhcp.leases)
no_client=$(awk '/duid/ {exit} {count++} END {print count}' /tmp/dhcp.leases)

extract_dhcp_client() {
    json_output="{"
    timestp=$(echo "$1" | awk '{print $1}')
    expDate=$(date -d @"$timestp" 2>/dev/null)
    mac=$(echo "$1" | awk '{print $2}')
    ip=$(echo "$1" | awk '{print $3}')
    hostname=$(echo "$1" | awk '{print $4}')

    json_output="${json_output}\"expDate\":\"${expDate}\""
    [ -n "$mac" ] && json_output="${json_output},\"mac\":\"${mac}\""
    [ -n "$ip" ] && json_output="${json_output},\"ip\":\"${ip}\""
    [ -n "$hostname" ] && json_output="${json_output},\"hostname\":\"${hostname}\""

    json_output="${json_output}}"

    echo "$json_output"
}

if [ -z "$client_data" ]; then
    json_obj={}
else
    i=1
    json_obj=$(echo "$client_data" | while read line; do
        extract_dhcp_client "$line"

        i=$((i + 1))
        [ "$i" -gt "$no_client" ] && break
    done)
fi

joined=$(echo "$json_obj" | tr '\n' ',' | sed 's/,$//')\

json_arr="[$joined]"

echo "$json_arr"
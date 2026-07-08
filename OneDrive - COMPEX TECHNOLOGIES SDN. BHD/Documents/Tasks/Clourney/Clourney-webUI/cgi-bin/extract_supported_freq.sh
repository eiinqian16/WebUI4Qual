#!/bin/sh

# Set content type to json
echo "Content-Type: application/json"
echo ""  # Separate header from body

extract_freq() {
    parent=$1
    freq=$(cat /sys/class/net/"$parent"/supported_freq_list)

    json_output="{\"${parent}\": ["$(echo $freq | sed 's/ /, /g')"]}"
    echo "$json_output"
}

dir="/sys/class/net"

# Use find to get all interfaces starting with "ath*" and capture the output of the loop.
# Each line will be one JSON object.
json_objects=$(find "$dir" -maxdepth 1 -name "wifi*" | while read -r file; do
    filename=$(basename "$file")
    extract_freq "$filename"
done)

# Now join the JSON objects with commas.
# Replace newline characters with commas and remove any trailing comma.
joined=$(echo "$json_objects" | tr '\n' ',' | sed 's/,$//')

# form a JSON array.
json_array="[$joined]"

# final JSON array
echo "$json_array"
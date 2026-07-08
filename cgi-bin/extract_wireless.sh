#!/bin/sh

# Set content type to json
echo "Content-Type: application/json"
echo ""  # Separate header from body

# Function to extract data for each interface
extract_data() {

    iwinfo_output=$(iwinfo "$1" info)

    iface=$(echo "$1")
    ssid=$(echo "$iwinfo_output" | grep -i "essid" | awk -F ':' '{print $2}' | awk -F '"' '{print $2}' | awk '{print $1}')
    mode=$(echo "$iwinfo_output" | grep -i "mode" | awk -F ':' '{print $2; exit}' | awk '{print $1}')
    frequency=$(echo "$iwinfo_output" | grep -i "channel" | awk -F '[()]' '{print $2}' | awk '{print $1}')
    access_point=$(echo "$iwinfo_output" | grep -i "access point" | awk '{print $3}')
    bit_rate=$(echo "$iwinfo_output" | grep -i "bit rate" | awk '{print $3}')
    tx_power=$(echo "$iwinfo_output" | grep -i "tx-power" | awk -F ':' '{print $2; exit}' | awk '{print $1}')
    enc_key=$(echo "$iwinfo_output" | grep -i "encryption" | awk -F ':' '{print $2}' | awk '{print $1}')
    link_quality=$(echo "$iwinfo_output" | grep -i "link quality" | awk -F ':' '{print $3; exit}' | awk '{print $1}')
    signal_level=$(echo "$iwinfo_output" | grep -i "signal" | awk -F ':' '{print $2; exit}' | awk '{print $1}')
    noise_level=$(echo "$iwinfo_output" | grep -i "noise" | awk -F ':' '{print $2}' | awk '{print $1}')
    mac=$(ifconfig "$1" | awk -F 'HWaddr' '{print $2}')
    channel=$(echo "$iwinfo_output" | grep -i "channel" | awk -F ':' '{print $3; exit}' | awk '{print $1}')
    htmode=$(echo "$iwinfo_output" | grep -i "ht mode" | awk -F ':' '{print $4; exit}' | awk '{print $1}')

    # Determine network type
    parent=$(cat /sys/class/net/"$1"/parent);
    if [[ "$frequency" == 2* ]]; then
        network="2G"
    elif [[ "$frequency" == 5* ]]; then
        network="5G"
    elif [[ "$frequency" == 6* ]]; then
        network="6G"
    else
        network="N/A"
    fi

    # Build the JSON object (be sure not to include a trailing comma)
    json_output="{"
    json_output="${json_output}\"Network\":\"${network}\""
    [ -n "$iface" ]         && json_output="${json_output},\"iface\":\"${iface}\""
    [ -n "$essid" ]         && json_output="${json_output},\"ESSID\":\"${essid}\""
    [ -n "$mode" ]          && json_output="${json_output},\"Mode\":\"${mode}\""
    [ -n "$frequency" ]     && json_output="${json_output},\"Frequency\":\"${frequency}\""
    [ -n "$access_point" ]  && json_output="${json_output},\"AccessPoint\":\"${access_point}\""
    [ -n "$bit_rate" ]      && json_output="${json_output},\"BitRate\":\"${bit_rate}\""
    [ -n "$tx_power" ]      && json_output="${json_output},\"TxPower\":\"${tx_power}\""
    [ -n "$enc_key" ]       && json_output="${json_output},\"EncryptionKey\":\"${enc_key}\""
    [ -n "$link_quality" ]  && json_output="${json_output},\"LinkQuality\":\"${link_quality}\""
    [ -n "$signal_level" ]  && json_output="${json_output},\"SignalLevel\":\"${signal_level}\""
    [ -n "$noise_level" ]   && json_output="${json_output},\"NoiseLevel\":\"${noise_level}\""
    [ -n "$mac" ]           && json_output="${json_output},\"macAddr\":\"${mac}\""
    [ -n "$channel" ]       && json_output="${json_output},\"channel\":\"${channel}\""
    [ -n "$htmode" ]       && json_output="${json_output},\"htmode\":\"${htmode}\""
    json_output="${json_output}}"

    echo "$json_output"
}

# Directory of WiFi interfaces 
dir="/sys/class/net"

# Use find to get all interfaces starting with "ath*" and capture the output of the loop.
# Each line will be one JSON object.
json_objects=$(find "$dir" -maxdepth 1 -name "wlan*" | while read -r file; do
    filename=$(basename "$file")
    extract_data "$filename"
done)

# Now join the JSON objects with commas.
# Replace newline characters with commas and remove any trailing comma.
joined=$(echo "$json_objects" | tr '\n' ',' | sed 's/,$//')

# form a JSON array.
json_array="[$joined]"

# final JSON array
echo "$json_array"


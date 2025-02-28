#!/bin/sh

# Set content type to json
echo "Content-Type: application/json"
echo ""  # Separate header from body

# Function to extract data for each interface
extract_data() {
    # Run iwconfig and capture output
    iwconfig_output=$(iwconfig "$1")

    # Determine network type
    parent=$(cat /sys/class/net/"$1"/parent);
    band=$(cat /sys/class/net/"$parent"/supported_bands);
    if [[ "$band" == 2* ]]; then
        network="2G"
    elif [[ "$band" == 5* ]]; then
        network="5G"
    elif [[ "$band" == 6* ]]; then
        network="6G"
    else
        network="N/A"
    fi

    # Extract various fields (adjust the commands as needed)
    iface=$(echo "$1")
    essid=$(echo "$iwconfig_output" | grep "ESSID:" | awk -F':' '{print $2}' | tr -d '"' | tr -d ' ')
    mode=$(echo "$iwconfig_output" | grep "Mode:" | awk -F ':' '{print $2}' | awk '{print $1}')
    frequency=$(echo "$iwconfig_output" | grep "Frequency:" | awk -F ':' '{print $3}' | awk '{print $1, $2}')
    access_point=$(echo "$iwconfig_output" | grep "Access Point:" | awk '{print $6}')
    bit_rate=$(echo "$iwconfig_output" | grep "Bit Rate:" | awk -F ':' '{print $2}' | awk '{print $1, $2}')
    tx_power=$(echo "$iwconfig_output" | grep "Tx-Power:" | awk -F ':' '{print $3}' | awk '{print $1, $2}')
    enc_key=$(echo "$iwconfig_output" | grep "Encryption key:" | awk -F ':' '{print $2}' | awk '{print $1}')
    link_quality=$(echo "$iwconfig_output" | grep "Link Quality=" | awk -F '=' '{print $2}' | awk '{print $1}')
    signal_level=$(echo "$iwconfig_output" | grep "Signal level=" | awk -F '=' '{print $3}' | awk '{print $1}')
    noise_level=$(echo "$iwconfig_output" | grep "Noise level=" | awk -F '=' '{print $4}' | awk '{print $1, $2}')
    mac=$(ifconfig "$1" | awk -F 'HWaddr' '{print $2}')

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
    json_output="${json_output}}"

    echo "$json_output"
}

# Directory of WiFi interfaces 
dir="/sys/class/net"

# Use find to get all interfaces starting with "ath*" and capture the output of the loop.
# Each line will be one JSON object.
json_objects=$(find "$dir" -maxdepth 1 -name "ath*" | while read -r file; do
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

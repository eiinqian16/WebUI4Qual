#!/bin/sh

# Set content type to json
echo "Content-Type: application/json"
echo ""

extract_data() {
    # Run iwconfig and capture output
    iwconfig_output=$(iwconfig $1)

    # Initialize JSON object
    json_output='{'
    
    if [ $1 = "ath0" ]; then
        network="2g";
    elif [ $1 = "ath1" ]; then
        network="5g"
    else
        network="6g"
    fi

    # Extract ESSID
    essid=$(echo "$iwconfig_output" | grep "ESSID:" | awk -F':' '{print $2}' | tr -d '"' | tr -d ' ')

    # Extract Mode
    mode=$(echo "$iwconfig_output" | grep "Mode:" | awk -F ':' '{print $2}' | awk '{print $1}')

    # Extract Frequency
    frequency=$(echo "$iwconfig_output" | grep "Frequency:" | awk -F ':' '{print $3}'| awk '{print $1, $2}')

    # Extract Access Point (MAC address)
    access_point=$(echo "$iwconfig_output" | grep "Access Point:" | awk '{print $6}')

    # Extract Bit Rate
    bit_rate=$(echo "$iwconfig_output" | grep "Bit Rate:" | awk -F ':' '{print $2}'| awk '{print $1, $2}')

    # Extract Tx-Power
    tx_power=$(echo "$iwconfig_output" | grep "Tx-Power:" | awk -F ':' '{print $3}'| awk '{print $1, $2}')

    # Extract Encryption Key
    enc_key=$(echo "$iwconfig_output" | grep "Encryption key:" | awk -F ':' '{print $2}'| awk '{print $1}')

    # Extract link quality
    link_quality=$(echo "$iwconfig_output" | grep "Link Quality=" | awk -F '=' '{print $2}' | awk '{print $1}')

    # Extract signal level
    signal_level=$(echo "$iwconfig_output" | grep "Signal level=" | awk -F '=' '{print $3}' | awk '{print $1}')

    # Extract noise level
    noise_level=$(echo "$iwconfig_output" | grep "Noise level=" | awk -F '=' '{print $4}' | awk '{print $1, $2}')

    # Extract mac addr
    mac=$(ifconfig $1 | awk -F 'HWaddr' '{print $2}')

    # Output to JSON file

    if [ ! -z "$network" ]; then
        json_output="$json_output\"Network\":\"$network\","
    fi

    if [ ! -z "$essid" ]; then
        json_output="$json_output\"ESSID\":\"$essid\","
    fi

    if [ ! -z "$mode" ]; then
        json_output="$json_output\"Mode\":\"$mode\","
    fi

    if [ ! -z "$frequency" ]; then
        json_output="$json_output\"Frequency\":\"$frequency\","
    fi

    if [ ! -z "$access_point" ]; then
        json_output="$json_output\"AccessPoint\":\"$access_point\","
    fi

    if [ ! -z "$bit_rate" ]; then
        json_output="$json_output\"BitRate\":\"$bit_rate\","
    fi
    if [ ! -z "$tx_power" ]; then
        json_output="$json_output\"TxPower\":\"$tx_power\","
    fi

    if [ ! -z "$enc_key" ]; then
        json_output="$json_output\"EncryptionKey\":\"$enc_key\","
    fi

    if [ ! -z "$link_quality" ]; then
        json_output="$json_output\"LinkQuality\":\"$link_quality\","
    fi

    if [ ! -z "$signal_level" ]; then
        json_output="$json_output\"SignalLevel\":\"$signal_level\","
    fi

    if [ ! -z "$noise_level" ]; then
        json_output="$json_output\"NoiseLevel\":\"$noise_level\","
    fi

    if [ ! -z "$mac" ]; then
        json_output="$json_output\"macAddr\":\"$mac\","
    fi

    #Remove trailing comma
    json_output="${json_output%,*}"

    # Close JSON object
    json_output="$json_output}"

    echo "$json_output"
}

dir="/sys/class/net" 
find "$dir" -maxdepth 1 -name "ath*" | while read -r file; do
    filename=$(basename "$file")
    echo $filename
    extract_data "$filename"
done


# Output to file
# echo "$json_output" > /www/test/data/iwconfig_$1.json

# echo "Output saved to iwconfig_$1.json"
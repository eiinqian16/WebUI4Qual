#!/bin/sh
# Extract supported 2.4GHz and 5GHz frequencies per Wi-Fi PHY into separate files

base_dir="/tmp/sysnet"
mkdir -p "$base_dir"

for phy in /sys/class/ieee80211/*; do
    [ -d "$phy" ] || continue
    phyname=$(basename "$phy")

    iface=$(iw dev | grep -A1 "$phyname" | grep Interface | awk '{print $2}' | head -n1)
    [ -z "$iface" ] && iface="${phyname/phy/wlan}"

    out_dir="$base_dir/$iface"
    mkdir -p "$out_dir"
    out_file="$out_dir/supported_freq_list"

    echo "Extracting frequencies for $phyname ($iface)..."

    iw phy "$phyname" info 2>/dev/null | grep -E "MHz" | \
        awk '{print $2}' | \
        grep -E '^[0-9]+$' | \
        awk '$1 >= 2412 && $1 <= 2484 || $1 >= 5180 && $1 <= 5885 || $1 >=5955 && $1 <= 7115' | \
        tr '\n' ' ' | sed 's/[[:space:]]*$//' > "$out_file"
    
    if [ -s "$out_file" ]; then 
        echo "Saved $(wc -w < "$out_file") valid freqs to $out_file"
    else
        echo "No valid frequencies found for $iface"
    fi        
done

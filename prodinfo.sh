#!/bin/sh

ICCID_FILE="/tmp/modem_iccid"
OUTFILE="/www/webUI/prod/info.txt"

mkdir -p "$(dirname "$OUTFILE")"
exec >"$OUTFILE"

get_iccid() {
    local slot=$1
    local iccid_file="${ICCID_FILE}_${slot}"

    # Read from cached file created by SIM detection scripts
    if [ -f "$iccid_file" ]; then
        grep -o '"iccid":"[^"]*"' "$iccid_file" | cut -d'"' -f4
    else
        echo "NA"
    fi
}

# Main information gathering
FW=$(cat /www/webUI/ov/fw_version 2>/dev/null)
echo "Firmware version: ${FW:-N/A}"

# Get wireless MAC addresses
echo "radio MAC (wlan0): $(cat /sys/class/net/wlan0/address 2>/dev/null || echo 'N/A')"
echo "radio MAC (wlan1): $(cat /sys/class/net/wlan1/address 2>/dev/null || echo 'N/A')"

# Get ethernet MAC addresses
echo "ethernet MAC (eth0): $(cat /sys/class/net/eth0/address 2>/dev/null || echo 'N/A')"
echo "ethernet MAC (eth1): $(cat /sys/class/net/eth1/address 2>/dev/null || echo 'N/A')"
echo "ethernet MAC (br-lan): $(cat /sys/class/net/br-lan/address 2>/dev/null || echo 'N/A')"

# Get model name
MODEL=$(cat /www/webUI/ov/model 2>/dev/null)
echo "Model Name: ${MODEL:-N/A}"

NAND_LINE=$(grep -i 'spi-nand' /tmp/syslog | grep -iE 'MiB|GiB' | tail -1)

if [ -n "$NAND_LINE" ]; then
    # 2. Extract the number and unit using standard awk (handles both MiB and GiB)
    NAND_MB=$(echo "$NAND_LINE" | awk '
        {
            for(i=1;i<=NF;i++) {
                if($i ~ /^[0-9]+$/ || $i ~ /^[0-9]+\.[0-9]+$/) {
                    val=$i; unit=$(i+1);
                    if(unit ~ /[Gg][Ii][Bb]/) { printf "%.0f\n", val * 1024; exit }
                    if(unit ~ /[Mm][Ii][Bb]/) { printf "%.0f\n", val; exit }
                }
            }
        }
    ')
fi

if [ -n "$NAND_MB" ]; then
    echo "NAND size: ${NAND_MB} MB"
else
    echo "NAND size: N/A"
fi

SYS_RAM=$(grep -i "Memory:" /tmp/syslog | head -1 | awk -F'/' '{print $2}' | awk '{print $1}' | tr -d 'Kk')

if [ -n "$SYS_RAM" ]; then
    RAM_SIZE=$((SYS_RAM / 1024))
else
    # Fallback to standard MemTotal if syslog dropped the early boot lines
    RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    RAW_MB=$((RAM_KB / 1024))
    # Round up to standard hardware sizes
    [ $RAW_MB -gt 128 ] && [ $RAW_MB -le 256 ] && RAM_SIZE=256
    [ $RAW_MB -gt 64 ] && [ $RAW_MB -le 128 ] && RAM_SIZE=128
    [ $RAW_MB -gt 256 ] && [ $RAW_MB -le 512 ] && RAM_SIZE=512
fi

echo "RAM size: ${RAM_SIZE:-N/A} MB"

# Get ethernet port status and speed
for iface in eth0 eth1; do
    if [ -e "/sys/class/net/$iface" ]; then
        # Check if interface is up via operational state file (faster than spawning 'ip link')
        if grep -q "up" "/sys/class/net/$iface/operstate" 2>/dev/null; then
            status="up"
        else
            status="down"
        fi
        echo "ethernet port status ($iface): $status"

        # Get speed (if available)
        if [ -e "/sys/class/net/$iface/speed" ]; then
            speed=$(cat "/sys/class/net/$iface/speed" 2>/dev/null)
            if [ "$speed" = "-1" ] || [ -z "$speed" ]; then
                echo "ethernet speed ($iface): unknown"
            else
                echo "ethernet speed ($iface): $speed Mbps"
            fi
        fi
    fi
done

MODEM=$(cat /tmp/modem_model 2>/dev/null)
echo "Modem Name: ${MODEM:-N/A}"

# Get SIM ICCID information
echo "SIM1 ICCID: $(get_iccid 1)"
echo "SIM2 ICCID: $(get_iccid 2)"
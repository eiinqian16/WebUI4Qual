#!/bin/sh
echo "Content-Type: text/plain"
echo ""

LOG_FILE="/tmp/wifi_config.log"

echo "---- New Request ----" >> $LOG_FILE
date >> $LOG_FILE

CONTENT_LENGTH=$(env | grep CONTENT_LENGTH | cut -d= -f2)
INPUT=$(dd bs=1 count=$CONTENT_LENGTH 2>/dev/null)

echo "Input JSON: $INPUT" >> $LOG_FILE

iface=$(echo "$INPUT" | jsonfilter -e '@.iface')

echo "Received iface: $iface" >> $LOG_FILE

if [ -z "$iface" ]; then
    echo "Error: No iface provided." >> $LOG_FILE
    echo "Error: No iface provided."
    exit 1
fi

echo "Deleting wireless.$iface..." >> $LOG_FILE
uci delete "wireless.$iface" >> $LOG_FILE 2>&1
uci commit wireless >> $LOG_FILE 2>&1

echo "Reloading WiFi..." >> $LOG_FILE
wifi reload >> $LOG_FILE 2>&1

echo "Done" >> $LOG_FILE
echo "Done"


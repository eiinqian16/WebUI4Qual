#! /bin/sh

MODEM_DEV="/dev/ttyUSB2"
STATE_FILE="/tmp/simstate"

[ -f /tmp/current_slot ] && current_slot=$(cat /tmp/current_slot) || current_slot=1

at_cmd() {
    local response=""
    # Open FD 3
    exec 3<> "$MODEM_DEV"
    # Send command
    printf "%s\r\n" "$1" >&3
    # Read response
    response=$(timeout 2 cat <&3 2>/dev/null | tr -d '\r')
    # Close FD 3
    exec 3>&-
    echo "$response"
}

while true; do 
    if [ ! -c "$MODEM_DEV" ]; then
        echo "Waiting for modem device ..."
        sleep 10
        continue
    fi

    echo "Modem found. Monitoring slot $current_slot ..."

    cat "$MODEM_DEV" | while read -r line; do
        clean=$(echo "$line" | tr -d '\r')

        case "$clean" in
            *"+CPIN: READY"*|*"+QSIMSTAT: 1,1"*)
                logger -t "MODEM" "SIM found in slot $current_slot. Configuring ..."
                echo "inserted" > "$state_file"
                /usr/bin/config_auto_apn.sh
                ;;

            *"+QSIMSTAT: 1,0"*|*"+CPIN: NOT INSERTED"*|*"+CME ERROR: 10"*)
                echo "removed" > "$STATE_FILE"
                other_slot=$([ "$current_slot" = "1" ] && echo "2" || echo "1")
                logger -t "MODEM" "Slot $current_slot empty. Trying slot $other_slot ..."
                break 2
                ;;
        esac
    done

    if [ "$(cat "STATE_FILE" 2>/dev/null)" = "removed" ]; then
        current_slot=$([ "current_slot" = "1" ] && echo "2" || echo "1")
        echo "$current_slot" > /tmp/current_slot
        sleep
        at_cmd "AT+QUIMSLOT=$current_slot"
        sleep 4
    fi
done
#! /bin/sh
#QUERY_STRING="action=add&mac=00:11:22:33:44:55&ssid=2g-clourney&policy=deny"
SSID=$(echo "$QUERY_STRING" | sed -n 's/^.*ssid=\([^&]*\).*$/\1/p')
ACTION=$(echo "$QUERY_STRING" | sed -n 's/^.*action=\([^&]*\).*$/\1/p')
POLICY=$(echo "$QUERY_STRING" | sed -n 's/^.*policy=\([^&]*\).*$/\1/p')
MAC=$(echo "$QUERY_STRING" | sed -n 's/^.*mac=\([^&]*\).*$/\1/p' | sed 's/%3A/:/g' | tr 'a-z' 'A-Z')
LOG="/tmp/sta_kickout.log"

echo "Content-type: application/json"
echo ""

if [ $(uci get wireless.default_radio0.ssid) == "$SSID" ]; then
    radio="wlan0"
elif [ $(uci get wireless.default_radio1.ssid) == "$SSID" ]; then
    radio="wlan1"
else
    echo "{\"ssid\":\"error\",\"message\":\"$SSID not found in device\"}" > $LOG
    exit 1
fi

if [ -z "$ACTION" ]; then
    echo "{\"action\":\"error\",\"message\":\"No action provided\"}" >> $LOG
    exit 1
fi

if [ -z "$MAC" ]; then
    echo "{\"status\": \"error\", \"message\": \"No MAC provided\"}" >> $LOG
    exit 1
fi

cur_policy=$(clsapi get macfilter_policy "$radio")
case "$POLICY" in 
    deny)
        if [ "$cur_policy" == "$POLICY" ]; then
            echo "{\"cur_policy\":\"info\",\"message\":\"Current policy same as needed policy\"}" >> $LOG
        else 
            clsapi set macfilter_policy "$radio" "$POLICY"
            echo "{\"cur_policy\":\"info\",\"message\":\"Current policy same as needed policy\"}" >> $LOG
        fi
    ;;
    allow)
        # to be implemented
    ;;
esac

case "$ACTION" in
    remove)
        if ! clsapi get macfilter_maclist "$radio" | grep -qi "$MAC"; then
            echo "{\"status\": \"info\", \"message\": \"$MAC not found in deny list\"}" >> $LOG
        else
            clsapi del macfilter_mac "$radio" "$MAC" > /dev/null 2>&1
            wifi > /dev/null 2>&1
            echo "{\"status\": \"success\", \"message\": \"$MAC removed from deny list\"}" >> $LOG
        fi
        ;;
    add)
        if clsapi get macfilter_maclist "$radio" | grep -qi "$MAC"; then
            echo "{\"status\": \"info\", \"message\": \"$MAC already in deny list\"}" >> $LOG
        else
            clsapi add macfilter_mac "$radio" "$MAC" > /dev/null 2>&1
            wifi > /dev/null 2>&1
            echo "{\"status\": \"success\", \"message\": \"$MAC added to deny list\"}" >> $LOG
        fi
        ;;
esac

if ! grep -qi "error" "$LOG"; then 
    echo "{\"result\":\"success\"}"
else
    echo "{\"result\":\"fail\"}"
fi
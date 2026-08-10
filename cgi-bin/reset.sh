#!/bin/sh

echo "Content-Type: text/plain"
echo ""
echo "Reset script triggered."

MODEM_DEV="/dev/ttyUSB2"
MODEM_MODEL=$(cat /tmp/modem_model 2>/dev/null)

case "$MODEM_MODEL" in
    "SRM810")
        RESET_CMD="AT+RESTORE=0"
        ;;
    "RG255"*)
        RESET_CMD='AT+QCFG="ResetFactory"'
        ;;
    "RM500U"|"RM500U-"*)
        RESET_CMD='AT+QCFG="ResetFactory"'
        ;;
    "Asrmicro"|"A7908E")
        RESET_CMD="AT&F"
        ;;
    *)
        RESET_CMD="AT+CFUN=1,1"
        ;;
esac

resp=$(echo -e "$RESET_CMD\r" | microcom -t 3000 $MODEM_DEV 2>/dev/null)

if echo "$resp" | grep -q "OK"; then
    echo "Modem reset command ($RESET_CMD): OK"

    echo "Executing modem reboot ..."
    echo "AT+CFUN=1,1" | microcom -t 500 "$MODEM_DEV"
    sleep 20

    echo "Restoring factory settings ..."
    clsapi restore factory

    echo "System rebooting now ..."
    clsapi trigger system_reboot
else 
    echo "Error: Modem did not respond with OK. Modem not reset."
    echo "Response received: $resp"
fi
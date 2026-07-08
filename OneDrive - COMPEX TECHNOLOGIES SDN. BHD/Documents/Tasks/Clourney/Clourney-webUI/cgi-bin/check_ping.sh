#!/bin/sh
echo "Content-Type: application/json"
echo ""

if ping -I usb0 -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    echo '{"ping":"ok"}'
else
    echo '{"ping":"fail"}'
fi
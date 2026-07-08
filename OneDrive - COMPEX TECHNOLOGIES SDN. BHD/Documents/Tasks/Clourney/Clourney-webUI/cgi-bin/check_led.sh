#!/bin/sh
echo "Content-Type: applicaton/json"
echo ""

LED_PATH="/sys/class/leds/green:status/brightness"

if [ -f "$LED_PATH" ] && [ "$(cat "$LED_PATH")" -gt 0 ]; then
    echo '{"led": "green"}'
else
    echo '{"led": "red"}'
fi
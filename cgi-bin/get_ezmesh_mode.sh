#!/bin/sh

echo "Content-Type: application/json"
echo ""

# Get the current mode from UCI. -q suppresses errors if the config is missing.
ROLE=$(uci -q get cls-mesh.default.mode)

# Default to "none" if the value is not set
[ -z "$ROLE" ] && ROLE="none"

echo "{\"role\": \"$ROLE\"}"

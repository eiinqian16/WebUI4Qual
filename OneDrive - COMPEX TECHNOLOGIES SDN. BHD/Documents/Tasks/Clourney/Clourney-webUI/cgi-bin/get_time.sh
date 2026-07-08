#!/bin/sh

echo "Content-Type: application/json"
echo ""

EPOCH=$(date +%s)

TZ_NAME=$(date +%Z)

cat <<EOF
{
    "epoch": $EPOCH,
    "timezone": "$TZ_NAME"
}
EOF
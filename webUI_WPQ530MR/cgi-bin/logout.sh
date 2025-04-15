#!/bin/sh

echo "Content-Type: application/json"
echo ""

SESSION_DIR="/tmp/sessions"

INPUT=$(cat)
session_id=$(echo "$INPUT" | sed -n 's/^.*session_id=\([^&]*\).*$/\1/p')

if [ -f "$SESSION_DIR/$session_id" ]; then
    rm -f "$SESSION_DIR/$session_id"
    printf '{"status":"Logged out"}\n'
else
    printf '{"status":"Session not found"}\n'
fi


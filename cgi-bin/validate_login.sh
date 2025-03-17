#!/bin/sh

echo "Content-Type: application/json"
echo ""

INPUT=$(cat)

nameInput=$(echo "$INPUT" | sed -n 's/^.*name=\([^&]*\).*$/\1/p' | sed 's/%20/ /g' | sed 's/+/ /g')
pwdInput=$(echo "$INPUT" | sed -n 's/^.*pwd=\([^&]*\).*$/\1/p' | sed 's/%20/ /g' | sed 's/+/ /g')

echo "Debug: nameInput='$nameInput', pwdInput='$pwdInput'" >&2  # 输出到系统日志

USER_DB="/etc/config/login"
SESSION_DIR="/tmp/sessions"

mkdir -p "$SESSION_DIR"

if grep -q "^$nameInput:" "$USER_DB"; then
    stored_pwd=$(grep "^$nameInput:" "$USER_DB" | awk -F':' '{print $2}')

    if [ -z "$pwdInput" ]; then
        pwdInputHash="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    else
        pwdInputHash=$(echo -n "$pwdInput" | sha256sum | awk '{print $1}')
    fi

    echo "Debug: stored_pwd='$stored_pwd', pwdInputHash='$pwdInputHash'" >&2  # 输出调试信息

    if [ "$pwdInputHash" = "$stored_pwd" ]; then
        session_id=$(cat /proc/sys/kernel/random/uuid)
        echo "$nameInput" > "$SESSION_DIR/$session_id"
        printf '{"status":"Success","session_id":"%s"}\n' "$session_id"
        exit 0
    else
        status="Incorrect password"
    fi
else
    status="Incorrect username"
fi

printf '{"status":"%s"}\n' "$status"


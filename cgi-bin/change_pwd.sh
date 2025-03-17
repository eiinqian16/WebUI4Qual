#!/bin/sh

echo "Content-Type: application/json"
echo ""  # Blank line to separate headers from body

read INPUT
#INPUT="uname=root&oriPwd=password&newPwd=newPassword"

nameInput=$(echo "$INPUT" | awk -F'[=&]' '{print $2}')
oriPwd=$(echo "$INPUT" | awk -F'[=&]' '{print $4}')
newPwd=$(echo "$INPUT" | awk -F'[=&]' '{print $6}')

dir="/etc/shadowUI"

encryptOriPwd=$(echo -n "$oriPwd" | sha256sum | awk '{print $1}')
encryptNewPwd=$(echo -n "$newPwd" | sha256sum | awk '{print $1}')

status="Wrong credentials"

while IFS=":" read -r uname storedPwd; do
    if [ "$nameInput" = "$uname" ] && [ "$encryptOriPwd" = "$storedPwd" ]; then
        output="${uname}:${encryptNewPwd}"
        status="Success"
        echo "$output" > "$dir"
        break
    fi
done < "$dir"

output_json="{\"status\":\"$status\"}"
echo "$output_json"
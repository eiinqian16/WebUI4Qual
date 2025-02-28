#!/bin/sh


# Set content type to json
echo "Content-Type: application/json"
echo ""  # Separate header from body

read INPUT
#INPUT="name=root&pwd=password"

nameInput=$(echo "$INPUT" | awk -F'[=&]' '{print $2}')
pwdInput=$(echo "$INPUT" | awk -F'[=&]' '{print $4}')

#echo "$nameInput"
#echo "$pwdInput"

dir=/etc/shadowUI

if grep -q "^$nameInput:" "$dir"; then
    stored_pwd=$(grep "^$nameInput:" "$dir" | awk -F':' '{print $2}')
    
    # Hash the entered password and compare
    pwdInputHash=$(echo -n "$pwdInput" | sha256sum | awk '{print $1}')

    if [ "$pwdInputHash" = "$stored_pwd" ]; then
        status="Success"
    else
        status="Incorrect password"
    fi
else
    status="Incorrect username"
fi

# Output JSON response
json_output="{\"status\":\"$status\"}"
echo "$json_output"

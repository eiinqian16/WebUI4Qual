#!/bin/sh

echo "Content-Type: application/json"
echo ""

file="/tmp/sysupgrade.bin"

cat > "$file"

if [ ! -f "$file" ]; then
    echo '{"error":"upload failed"}'
    exit 1
fi 

check=$(sysupgrade --test $file)
if echo "$check" | grep -q "error"; then
    echo '{"error":"image validation failed"}'
else
    status="Image validation passed"
fi

md5sum=$(md5sum "$file" | awk '{print $1}')
sha256sum=$(sha256sum "$file" | awk '{print $1}')

echo "{\"md5\": \"$md5sum\", \"sha256\": \"$sha256sum\", \"status\": \"$status\"}"
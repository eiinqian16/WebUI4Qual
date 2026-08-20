#!/bin/sh

echo "Content-Type: text/plain"
echo ""

tmp_img="/tmp/sysupgrade.bin"

if [ ! -f "$tmp_img" ]; then
    echo "No uploaded image found!"
    exit 1
fi

echo "Upgrade would start with image: $tmp_img"

#upgrade 
sysupgrade -v /tmp/sysupgrade.bin
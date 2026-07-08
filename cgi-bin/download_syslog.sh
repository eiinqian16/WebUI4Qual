#!/bin/sh

echo "Content-Type: application/octet-stream"
echo "Content-Disposition: attachment; filename=syslog.txt"
echo ""

cat /tmp/syslog 2>/dev/null || echo "No syslog found"
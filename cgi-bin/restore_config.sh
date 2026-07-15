#!/bin/sh
echo "Content-Type: application/json"
echo ""

uploaded="/tmp/uploaded_backup.tar.gz"

if [ -z "$uploaded" ]; then
    echo "{\"status\":\"error\",\"message\":\"No file uploaded\"}"
    exit 1
fi

if sysupgrade --restore-backup "$uploaded" > /tmp/restore.log 2>&1; then
    echo "{\"status\":\"success\", \"file\":\"$FILE_NAME\"}"
else
    echo "{\"status\":\"error\", \"message\":\"Restore failed. Check /tmp/restore.log.\"}"
fi
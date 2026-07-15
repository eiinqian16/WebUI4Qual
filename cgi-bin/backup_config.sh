#!/bin/sh
echo "Content-type: application/json"
echo ""

BACKUP_DIR="/etc/backup"
DATE=$(date +%Y-%m-%d_%H%M)
FILE="${BACKUP_DIR}/${DATE}_config_backup.tar.gz"
FILE_NAME="${DATE}_config_backup.tar.gz"

[ ! -d "$BACKUP_DIR" ] && mkdir -p "$BACKUP_DIR"

sysupgrade -b "$FILE"

if [ $? -eq 0 ]; then
    echo "{\"status\":\"success\", \"file\":\"$FILE\", \"filename\":\"$FILE_NAME\"}"
else
    echo "{\"status\":\"error\"}"
fi


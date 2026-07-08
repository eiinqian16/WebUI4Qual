#!/bin/sh

file=$(echo "$QUERY_STRING" | sed -n 's/^file=//p')

# Default if not specified
[ -z "$file" ] && file="config_backup.tar.gz"

BACKUP_DIR="/etc/backup"
BACKUP_FILE="$BACKUP_DIR/$file"

# Ensure the file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo "Status: 404 Not Found"
    echo "Content-Type: text/plain"
    echo ""
    echo "Backup file not found."
    exit 1
fi

# Set headers for file download
echo "Content-Type: application/octet-stream"
echo "Content-Disposition: attachment; filename=\"$file\""
echo ""

# Output file contents
cat "$BACKUP_FILE"

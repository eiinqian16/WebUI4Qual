#!/bin/sh
echo "Content-Type: application/json"
echo ""

UPLOAD_DIR="/tmp"
FILE_NAME="uploaded_backup.tar.gz"
FILE_PATH="${UPLOAD_DIR}/${FILE_NAME}"

# Read raw binary data directly from stdin and write to file
cat > "$FILE_PATH"

# Verify that upload succeeded
if [ ! -s "$FILE_PATH" ]; then
    echo '{"error":"File upload failed or file is empty"}'
    exit 1
fi

# Compute MD5 and SHA256
MD5_SUM=$(md5sum "$FILE_PATH" | awk '{print $1}')
SHA256_SUM=$(sha256sum "$FILE_PATH" | awk '{print $1}')

# Return JSON response
echo "{\"status\":\"success\",\"path\":\"$FILE_PATH\",\"md5\":\"$MD5_SUM\",\"sha256\":\"$SHA256_SUM\"}"

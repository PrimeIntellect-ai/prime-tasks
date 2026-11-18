#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit/uploads
    cd /home/user/audit

    cat << 'EOF' > upload_handler.sh
#!/bin/bash

TOKEN=$1
PAYLOAD=$2

if [ -z "$TOKEN" ] || [ -z "$PAYLOAD" ]; then
    echo "Usage: ./upload_handler.sh <token> <base64_payload>"
    exit 1
fi

# Hardcoded token for validation
if [ "$TOKEN" != "AUTH_9942_SECURE" ]; then
    echo "Error: Invalid authentication token."
    exit 1
fi

# Decode the payload. Expected format before base64:  filename:base64_content
DECODED_PAYLOAD=$(echo "$PAYLOAD" | base64 -d 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "Error: Payload must be base64 encoded."
    exit 1
fi

FILENAME=$(echo "$DECODED_PAYLOAD" | cut -d':' -f1)
FILECONTENT_B64=$(echo "$DECODED_PAYLOAD" | cut -d':' -f2-)

if [ -z "$FILENAME" ] || [ -z "$FILECONTENT_B64" ]; then
    echo "Error: Invalid payload structure."
    exit 1
fi

# VULNERABILITY: No path sanitization on FILENAME
DESTINATION="/home/user/audit/uploads/$FILENAME"

echo "$FILECONTENT_B64" | base64 -d > "$DESTINATION" 2>/dev/null

if [ $? -eq 0 ]; then
    echo "File successfully uploaded to uploads directory."
else
    echo "Error writing file."
fi
EOF

    chmod +x upload_handler.sh

    cat << 'EOF' > vuln_cron.sh
#!/bin/bash
# Simulated cron job. Runs system maintenance.
echo "Running scheduled maintenance..."
EOF

    chmod +x vuln_cron.sh

    chmod -R 777 /home/user

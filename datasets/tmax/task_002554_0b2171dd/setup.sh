#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_logs.jsonl
{"id": 1, "update_text": "Set timeout=60 and retries=3 for the database connection."}
{"id": 2, "update_text": "Update DB_PASSWORD=db_pass_123 \u005Z error in auth module"}
{"id": 3, "update_text": "Changed api_key=XYZ890 and port=8080"}
{"id": 4, "update_text": "Valid unicode \u2713 auth_token=abc123"}
{"id": 5, "update_text": "No configs here, just a status update \uG123"}
EOF

    chmod 644 /home/user/raw_logs.jsonl

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

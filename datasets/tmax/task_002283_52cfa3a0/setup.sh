#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_feedback.jsonl
{"id": "1", "timestamp": "2023-10-25T14:15:00Z", "user_email": "john.doe@example.com", "ip_address": "192.168.1.1", "text": "Great app!", "lang": "en"}
{"id": "2", "timestamp": "2023-10-25T14:59:59Z", "user_email": "maria@domain.es", "ip_address": "10.0.0.5", "text": "Me gusta", "lang": "es"}
{"id": "3", "timestamp": "2023-10-25T15:05:00Z", "user_email": "hacker@bad.com", "text": "Fix this bug.", "lang": ""}
{"id": "4", "timestamp": "2023-10-26T09:10:00Z", "user_email": "someone@test.com", "ip_address": "172.16.254.1", "text": "Bonjour", "lang": "fr"}
{"id": "5", "timestamp": "2023-10-26T09:45:00Z", "text": "Hello again", "lang": "en"}
{"id": "6", "user_email": "missingtime@test.com", "text": "No time", "lang": "en"}
EOF

    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_chat_logs.jsonl
{"ts": "2023-05-12T14:00:00Z", "user_id": "u1", "message": "Hello from admin@example.com "}
{"ts": "05/12/2023 14:01:00", "user_id": "u2", "message": "  Testing \ud83d\ude00"}
{"ts": 1683900180, "user_id": "u3", "message": "Reach out to support@test.org."}
{"ts": "2023-05-12T14:05:00Z", "user_id": "u1", "message": "Skip ahead"}
{"ts": "2023-05-12T14:06:00Z", "user_id": "u4", "message": "Bad escape \u00ZZ here"}
EOF

    chmod -R 777 /home/user

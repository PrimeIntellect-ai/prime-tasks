#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the input events file directly to ensure exact unicode escape sequences
    cat << 'EOF' > /home/user/events.jsonl
{"timestamp": "2024-03-10T14:23:05Z", "username": "j\u0064oe", "action": "LOGIN"}
{"timestamp": "2024-03-10T14:59:59Z", "username": "admin", "action": "LOGIN"}
{"timestamp": "2024-03-10T14:00:00Z", "username": "s\u006Dith", "action": "LOGOUT"}
{"timestamp": "2024-03-10T15:05:00Z", "username": "jdoe", "action": "READ"}
{"timestamp": "2024-03-10T15:10:00Z", "username": "a\u006Cice", "action": "READ"}
{"timestamp": "2024-03-11T09:15:22Z", "username": "\u0062ob", "action": "LOGIN"}
EOF

    chmod -R 777 /home/user

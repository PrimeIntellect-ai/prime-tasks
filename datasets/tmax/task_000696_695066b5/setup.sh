#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk sed coreutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_logs.jsonl
{"timestamp": "2023-10-01T10:15:00Z", "user": "alice", "action": "login"}
{"timestamp": "2023-10-01T10:25:30Z", "user": "alice", "action": "view"}
{"timestamp": "2023-10-01T10:45:00Z", "user": "bob", "action": "login"}
{"timestamp": "2023-10-01T11:05:00Z", "user": "alice", "action": "logout"}
{"timestamp": "2023-10-01T11:10:00Z", "user": "charlie", "action": "login\uXXXX"}
{"timestamp": "2023-10-01T11:15:00Z", "user": "bob", "action": "view"}
{"timestamp": "2023-10-01T11:20:00Z", "user": "bob", "action": "view"}
{"timestamp": "2023-10-01T11:45:00Z", "user": "alice", "action": "login"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

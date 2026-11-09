#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_logs.jsonl
{"timestamp":"2023-10-01T10:00:00Z","user_id":101,"email":"alice@domain.com","message":"Logged in successfully\x21"}
{"timestamp":"2023-10-01T10:05:00Z","user_id":null,"email":"bob.jones@work.org","message":"Checked profile"}
{"timestamp":"2023-10-01T10:10:00Z","user_id":103,"email":"charlie@home.net","message":"File uploaded\x2E"}
{"timestamp":"2023-10-01T10:15:00Z","user_id":null,"email":"david_99@test.io","message":"Warning\x3A disk space low"}
{"timestamp":"2023-10-01T10:20:00Z","user_id":105,"email":"eve@corp.com","message":"Process terminated with code \x30"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

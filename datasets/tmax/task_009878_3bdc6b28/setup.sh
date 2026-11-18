#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    # Create users.csv
    cat << 'EOF' > users.csv
id,username,role
1, Alice ,admin
2,BOB,user
3,  cHarLie,guest
4,DAVE ,user
EOF

    # Create access_logs.jsonl
    cat << 'EOF' > access_logs.jsonl
{"timestamp": "2023-10-01T10:05:12Z", "username": "alice", "endpoint": "/api/v1/data", "ip": "10.0.0.1"}
{"timestamp": "2023-10-01T10:05:45Z", "username": "ALICE", "endpoint": "/api/v1/data", "ip": "10.0.0.1"}
{"timestamp": "2023-10-01T10:06:12Z", "username": "alice", "endpoint": "/api/v1/data", "ip": "10.0.0.1"}
{"timestamp": "2023-10-01T10:05:12Z", "username": "bob", "endpoint": "/api/v1/data", "ip": "10.0.0.2"}
{"timestamp": "2023-10-01T10:05:12Z", "username": "charlie", "endpoint": "/api/v1/login", "ip": "10.0.0.3"}
{"timestamp": "2023-10-01T10:05:12Z", "username": "eve", "endpoint": "/api/v1/hack", "ip": "10.0.0.4"}
{"timestamp": "2023-10-01T10:05:59Z", "username": " bob ", "endpoint": "/api/v1/data", "ip": "10.0.0.2"}
{"timestamp": "2023-10-01T11:00:00Z", "username": "DAVE", "endpoint": "/api/v1/view", "ip": "10.0.0.5"}
EOF

    chmod -R 777 /home/user

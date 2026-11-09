#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/app_logs
    mkdir -p /home/user/condensed_logs

    cat << 'EOF' > /home/user/dict.csv
app-server-east-001,E1
app-server-west-002,W2
database-node-primary,DBP
ERR_OUT_OF_MEMORY,OOM
ERR_CONNECTION_TIMEOUT,CTO
EOF

    cat << 'EOF' > /home/user/app_logs/server1.jsonl
{"timestamp": "2023-10-01T10:00:00Z", "server_id": "app-server-east-001", "status": "FAILED", "error_code": "ERR_OUT_OF_MEMORY"}
{"timestamp": "2023-10-01T10:05:00Z", "server_id": "app-server-east-001", "status": "SUCCESS", "error_code": "NONE"}
{"timestamp": "2023-10-01T10:10:00Z", "server_id": "database-node-primary", "status": "FAILED", "error_code": "ERR_CONNECTION_TIMEOUT"}
EOF

    cat << 'EOF' > /home/user/app_logs/server2.jsonl
{"timestamp": "2023-10-02T11:00:00Z", "server_id": "app-server-west-002", "status": "FAILED", "error_code": "ERR_OUT_OF_MEMORY"}
{"timestamp": "2023-10-02T11:05:00Z", "server_id": "app-server-west-002", "status": "SUCCESS", "error_code": "NONE"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

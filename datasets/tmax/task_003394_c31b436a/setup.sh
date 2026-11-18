#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    mkdir -p /home/user/raw_logs

    # File 1: Standard UTF-8 with embedded newlines
    cat << 'EOF' > /home/user/raw_logs/server_a.csv
LogID,Timestamp,User,RawMessage
101,2023-10-01T10:00:00Z,alice,"User LOGIN successful
IP: 192.168.1.5"
102,2023-10-01T10:05:00Z,bob,"Connection TIMEOUT
Retrying..."
103,2023-10-01T10:10:00Z,alice,"User LOGOUT
Session ended."
104,2023-10-01T10:15:00Z,charlie,"Random system message
Nothing to see here"
EOF

    # File 2: Mixed encoding (simulated with raw bytes) and duplicates
    python3 -c '
import csv

data = [
    ["LogID", "Timestamp", "User", "RawMessage"],
    ["201", "2023-10-01T10:00:00Z", "alice", "User LOGIN successful\nIP: 192.168.1.5 (Duplicate event from Load Balancer)"],
    ["202", "2023-10-01T10:02:00Z", "dave", b"User LOGIN \xff invalid bytes".decode("latin-1")],
    ["203", "2023-10-01T10:05:00Z", "bob", "Connection TIMEOUT\nRetrying..."],
    ["204", "2023-10-01T10:12:00Z", "eve", "Standard LOGIN event"]
]

with open("/home/user/raw_logs/server_b.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerows(data)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/audit_logs.jsonl
{"event": "start", "req": "T1", "ts": 10000}
{"event": "read", "req": "T1", "ts": 10100, "payload": {"target": "R1"}}
{"event": "write", "req": "T1", "ts": 10200, "payload": {"target": "R1"}}
{"event": "start", "tx": "T2", "ts": 10300}
{"event": "write", "tx": "T2", "ts": 10600, "payload": {"target": "R1"}}
{"event": "commit", "req": "T1", "ts": 10700}
{"event": "write", "tx": "T2", "ts": 10800, "payload": {"target": "R2"}}
{"event": "start", "req": "T3", "ts": 10850}
{"event": "write", "req": "T3", "ts": 11000, "payload": {"target": "R2"}}
{"event": "commit", "tx": "T2", "ts": 11100}
{"event": "write", "req": "T3", "ts": 11500, "payload": {"target": "R3"}}
{"event": "start", "tx": "T4", "ts": 11600}
{"event": "write", "tx": "T4", "ts": 12100, "payload": {"target": "R3"}}
EOF

    chmod -R 777 /home/user

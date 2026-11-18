#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import json
import os

records = [
    {"tx_id": "tx01", "account_id": "A100", "start_time": 100, "end_time": 150, "operation": "UPDATE"},
    {"tx_id": "tx02", "account_id": "A100", "start_time": 140, "end_time": 160, "operation": "READ"},
    {"tx_id": "tx03", "account_id": "A100", "start_time": 170, "end_time": 200, "operation": "UPDATE"},
    {"tx_id": "tx04", "account_id": "A200", "start_time": 100, "end_time": 300, "operation": "UPDATE"},
    {"tx_id": "tx05", "account_id": "A200", "start_time": 250, "end_time": 350, "operation": "UPDATE"},
    {"tx_id": "tx06", "account_id": "A200", "start_time": 320, "end_time": 400, "operation": "READ"},
    {"tx_id": "tx07", "account_id": "A300", "start_time": 100, "end_time": 110, "operation": "UPDATE"},
    {"tx_id": "tx08", "account_id": "A400", "start_time": 500, "end_time": 600, "operation": "UPDATE"},
    {"tx_id": "tx09", "account_id": "A400", "start_time": 550, "end_time": 650, "operation": "UPDATE"},
    {"tx_id": "tx10", "account_id": "A400", "start_time": 620, "end_time": 700, "operation": "UPDATE"},
    {"tx_id": "tx11", "account_id": "A500", "start_time": 10, "end_time": 50, "operation": "UPDATE"},
    {"tx_id": "tx12", "account_id": "A500", "start_time": 40, "end_time": 80, "operation": "UPDATE"},
    {"tx_id": "tx13", "account_id": "A600", "start_time": 100, "end_time": 500, "operation": "UPDATE"},
    {"tx_id": "tx14", "account_id": "A600", "start_time": 200, "end_time": 300, "operation": "UPDATE"},
    {"tx_id": "tx15", "account_id": "A600", "start_time": 400, "end_time": 600, "operation": "UPDATE"},
    {"tx_id": "tx16", "account_id": "A700", "start_time": 1000, "end_time": 2000, "operation": "UPDATE"},
    {"tx_id": "tx17", "account_id": "A700", "start_time": 1500, "end_time": 2500, "operation": "UPDATE"},
    {"tx_id": "tx18", "account_id": "A800", "start_time": 1000, "end_time": 2000, "operation": "UPDATE"},
    {"tx_id": "tx19", "account_id": "A800", "start_time": 1500, "end_time": 2500, "operation": "UPDATE"},
    {"tx_id": "tx20", "account_id": "A900", "start_time": 1000, "end_time": 2000, "operation": "UPDATE"},
    {"tx_id": "tx21", "account_id": "A900", "start_time": 1500, "end_time": 2500, "operation": "UPDATE"}
]

os.makedirs('/home/user', exist_ok=True)
with open('/home/user/audit_logs.json', 'w') as f:
    json.dump(records, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

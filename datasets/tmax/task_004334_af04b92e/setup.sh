#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/transactions.jsonl
{"tx_id": "TX1", "action": "ACQUIRED", "resource": "RES_A", "timestamp": 100}
{"tx_id": "TX2", "action": "ACQUIRED", "resource": "RES_B", "timestamp": 101}
{"tx_id": "TX3", "action": "ACQUIRED", "resource": "RES_C", "timestamp": 102}
{"tx_id": "TX4", "action": "ACQUIRED", "resource": "RES_D", "timestamp": 103}
{"tx_id": "TX5", "action": "ACQUIRED", "resource": "RES_E", "timestamp": 104}
{"tx_id": "TX1", "action": "WAITING", "resource": "RES_B", "timestamp": 105}
{"tx_id": "TX2", "action": "WAITING", "resource": "RES_C", "timestamp": 106}
{"tx_id": "TX3", "action": "WAITING", "resource": "RES_A", "timestamp": 107}
{"tx_id": "TX6", "action": "WAITING", "resource": "RES_D", "timestamp": 108}
{"tx_id": "TX4", "action": "WAITING", "resource": "RES_E", "timestamp": 109}
EOF

    chmod -R 777 /home/user

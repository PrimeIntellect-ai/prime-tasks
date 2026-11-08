#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk coreutils grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/logs.jsonl
{"tx_id": "1", "src": "ROOT", "dst": "A", "amount": 50, "status": "SUCCESS"}
{"tx_id": "2", "src": "ROOT", "dst": "B", "amount": 30, "status": "SUCCESS"}
{"tx_id": "3", "src": "ROOT", "dst": "C", "amount": 10, "status": "SUCCESS"}
{"tx_id": "4", "src": "A", "dst": "D", "amount": 20, "status": "SUCCESS"}
{"tx_id": "5", "src": "A", "dst": "E", "amount": 10, "status": "FAILED"}
{"tx_id": "6", "src": "B", "dst": "D", "amount": 60, "status": "SUCCESS"}
{"tx_id": "7", "src": "B", "dst": "E", "amount": 80, "status": "SUCCESS"}
{"tx_id": "8", "src": "C", "dst": "F", "amount": 15, "status": "SUCCESS"}
{"tx_id": "9", "src": "C", "dst": "D", "amount": 90, "status": "SUCCESS"}
{"tx_id": "10", "src": "D", "dst": "G", "amount": 5, "status": "SUCCESS"}
{"tx_id": "11", "src": "ROOT", "dst": "X", "amount": 100, "status": "SUCCESS"}
{"tx_id": "12", "src": "X", "dst": "Y", "amount": 200, "status": "SUCCESS"}
{"tx_id": "13", "src": "Y", "dst": "Z", "amount": 300, "status": "SUCCESS"}
EOF

    chmod -R 777 /home/user

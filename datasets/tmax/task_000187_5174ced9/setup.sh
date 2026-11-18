#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_data.py
import json

with open("/home/user/telemetry.jsonl", "w") as f:
    valid_count = 0
    tx_id = 1

    # 1 to 50: valid, amount = 10.0
    for _ in range(50):
        f.write(json.dumps({"tx_id": tx_id, "amount": 10.0, "status": "ok"}) + "\n")
        tx_id += 1

    # 51: invalid json
    f.write('{"tx_id": ' + str(tx_id) + ', "amount": 10.0, "status": "ok"\n')
    tx_id += 1

    # 52: invalid (negative amount)
    f.write(json.dumps({"tx_id": tx_id, "amount": -5.0, "status": "ok"}) + "\n")
    tx_id += 1

    # 53: invalid (missing key)
    f.write(json.dumps({"tx_id": tx_id, "amount": 10.0}) + "\n")
    tx_id += 1

    # 54: valid, changepoint! MA of last 50 is 10.0. Amount = 31.0 (> 30.0)
    f.write(json.dumps({"tx_id": tx_id, "amount": 31.0, "status": "ok"}) + "\n")
    tx_id += 1

    # 55 to 103: valid, amount = 10.0
    for _ in range(49):
        f.write(json.dumps({"tx_id": tx_id, "amount": 10.0, "status": "ok"}) + "\n")
        tx_id += 1

    # At this point, the last 50 valid amounts are: one 31.0, and forty-nine 10.0s.
    # Sum = 31 + 490 = 521. Average = 10.42.
    # Threshold for next is 10.42 * 3 = 31.26

    # 104: valid, changepoint! Amount = 32.0 (> 31.26)
    f.write(json.dumps({"tx_id": tx_id, "amount": 32.0, "status": "ok"}) + "\n")
    tx_id += 1
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    chmod -R 777 /home/user

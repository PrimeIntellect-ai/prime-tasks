#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    # Create the memory dump
    python3 -c '
import os
with open("/home/user/sysdump.bin", "wb") as f:
    f.write(os.urandom(2048))
    f.write(b"\x00\x00Some logging data... \nFATAL_CRASH_TX_ID: TX-8374-ERR\n[TRACE] Segfault")
    f.write(os.urandom(1024))
'

    # Create the transactions log
    cat << 'EOF' > /home/user/transactions.txt
TX-1000-OK|{"amount": 150.50, "currency": "USD"}
TX-8374-ERR|{"amount": 9007199254740995.05, "currency": "USD", }
TX-9999-OK|{"amount": 10.0, "currency": "EUR"}
EOF

    # Create the buggy processor
    cat << 'EOF' > /home/user/processor.py
import json

def process_tx(tx_line):
    tx_line = tx_line.strip()
    if not tx_line:
        return None

    tx_id, payload = tx_line.split('|', 1)

    # Bug 1: Fails on trailing comma in TX-8374-ERR
    # Bug 2: precision loss on large floats in default json.loads
    data = json.loads(payload)

    amount = data['amount']
    # 5% tax
    tax = amount * 0.05

    return tx_id, amount, tax
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user

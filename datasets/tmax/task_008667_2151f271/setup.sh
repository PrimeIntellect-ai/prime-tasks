#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import json
import os

os.makedirs('/home/user/data', exist_ok=True)
os.makedirs('/home/user/output', exist_ok=True)

# Create SQLite DB
conn = sqlite3.connect('/home/user/data/financial.db')
c = conn.cursor()
c.execute('CREATE TABLE users (user_id TEXT PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE accounts (account_id TEXT PRIMARY KEY, user_id TEXT)')

users = [
    ('u1', 'Alice'),
    ('u2', 'Bob'),
    ('u3', 'Charlie'),
    ('u4', 'Diana'),
    ('u5', 'Eve'),
    ('u6', 'Frank')
]

accounts = [
    ('a1', 'u1'), ('a2', 'u1'), # Alice has two accounts
    ('a3', 'u2'),
    ('a4', 'u3'),
    ('a5', 'u4'),
    ('a6', 'u5'),
    ('a7', 'u6')
]

c.executemany('INSERT INTO users VALUES (?, ?)', users)
c.executemany('INSERT INTO accounts VALUES (?, ?)', accounts)
conn.commit()
conn.close()

# Create JSON Lines
transactions = [
    # Cycle 1: Alice (a1) -> Bob (a3) -> Charlie (a4) -> Alice (a2)
    {"tx_id": "t1", "from_account": "a1", "to_account": "a3", "amount": 100.0, "currency": "USD"},
    {"tx_id": "t2", "from_account": "a3", "to_account": "a4", "amount": 150.0, "currency": "USD"},
    {"tx_id": "t3", "from_account": "a4", "to_account": "a2", "amount": 200.0, "currency": "USD"},

    # Cycle 2: Diana (a5) -> Eve (a6) -> Frank (a7) -> Diana (a5)
    {"tx_id": "t4", "from_account": "a5", "to_account": "a6", "amount": 500.0, "currency": "USD"},
    {"tx_id": "t5", "from_account": "a6", "to_account": "a7", "amount": 300.0, "currency": "USD"},
    {"tx_id": "t6", "from_account": "a7", "to_account": "a5", "amount": 400.0, "currency": "USD"},

    # Noise / Dead ends
    {"tx_id": "t7", "from_account": "a1", "to_account": "a5", "amount": 50.0, "currency": "USD"},
    {"tx_id": "t8", "from_account": "a3", "to_account": "a6", "amount": 20.0, "currency": "USD"},
    # 2-Cycle (not a 3-cycle)
    {"tx_id": "t9", "from_account": "a2", "to_account": "a3", "amount": 10.0, "currency": "USD"},
    {"tx_id": "t10", "from_account": "a3", "to_account": "a2", "amount": 10.0, "currency": "USD"}
]

with open('/home/user/data/transactions.jsonl', 'w') as f:
    for tx in transactions:
        f.write(json.dumps(tx) + '\n')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

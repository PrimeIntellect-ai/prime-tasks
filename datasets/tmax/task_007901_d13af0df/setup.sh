#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest networkx jsonschema

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import sqlite3
import json
import os

db_path = '/home/user/transactions.db'
schema_path = '/home/user/schema.json'

# 1. Create SQLite DB
conn = sqlite3.connect(db_path)
cursor = conn.cursor()
cursor.execute('''
CREATE TABLE transactions (
    tx_id INTEGER PRIMARY KEY,
    sender TEXT,
    receiver TEXT,
    amount REAL,
    tx_date TEXT
)
''')

# Insert data
data = [
    (1, 'Alice', 'Bob', 100.0, '2023-01-10'),
    (2, 'Bob', 'Charlie', 60.0, '2023-01-15'),
    (3, 'Charlie', 'Alice', 20.0, '2023-01-20'),
    (4, 'Alice', 'David', 200.0, '2023-01-25'),
    (5, 'David', 'Eve', 150.0, '2023-01-28'),
    (6, 'Eve', 'Alice', 300.0, '2023-01-30'),
    (7, 'Bob', 'David', 80.0, '2023-02-05'),
    (8, 'Alice', 'Bob', 70.0, '2023-01-12')
]

cursor.executemany('INSERT INTO transactions VALUES (?, ?, ?, ?, ?)', data)
conn.commit()
conn.close()

# 2. Create JSON Schema
schema = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "properties": {
        "metadata": {
            "type": "object",
            "properties": {
                "threshold": {"type": "number"},
                "date_start": {"type": "string"},
                "date_end": {"type": "string"}
            },
            "required": ["threshold", "date_start", "date_end"]
        },
        "top_nodes": {
            "type": "array",
            "maxItems": 3,
            "items": {
                "type": "object",
                "properties": {
                    "account": {"type": "string"},
                    "pagerank": {"type": "number"}
                },
                "required": ["account", "pagerank"]
            }
        }
    },
    "required": ["metadata", "top_nodes"]
}

with open(schema_path, 'w') as f:
    json.dump(schema, f, indent=2)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user

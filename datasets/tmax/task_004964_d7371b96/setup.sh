#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import json
import os

db_path = '/home/user/data_lake.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cur = conn.cursor()
cur.execute("CREATE TABLE documents (id INTEGER PRIMARY KEY, doc TEXT)")

docs = [
    {"type": "user", "user_id": "U01", "name": "Alice"},
    {"type": "user", "user_id": "U02", "name": "Bob"},
    {"type": "user", "user_id": "U05", "name": "Eve"},

    {"type": "product", "product_id": "P01", "category": "book"},
    {"type": "product", "product_id": "P02", "category": "book"},
    {"type": "product", "product_id": "P03", "category": "book"},
    {"type": "product", "product_id": "P06", "category": "electronics"},
    {"type": "product", "product_id": "P07", "category": "home"},
    {"type": "product", "product_id": "P99", "category": "other"},

    {"type": "purchase", "user_id": "U01", "product_id": "P01"},
    {"type": "purchase", "user_id": "U01", "product_id": "P02"},
    {"type": "purchase", "user_id": "U01", "product_id": "P03"},
    {"type": "purchase", "user_id": "U01", "product_id": "P07"},

    {"type": "purchase", "user_id": "U02", "product_id": "P01"},
    {"type": "purchase", "user_id": "U02", "product_id": "P02"},
    {"type": "purchase", "user_id": "U02", "product_id": "P03"},
    {"type": "purchase", "user_id": "U02", "product_id": "P06"},

    {"type": "purchase", "user_id": "U05", "product_id": "P01"},
    {"type": "purchase", "user_id": "U05", "product_id": "P02"},
    {"type": "purchase", "user_id": "U05", "product_id": "P07"}
]

for d in docs:
    cur.execute("INSERT INTO documents (doc) VALUES (?)", (json.dumps(d),))

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user

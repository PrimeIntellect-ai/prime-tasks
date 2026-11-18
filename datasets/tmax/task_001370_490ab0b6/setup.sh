#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import json
import os

db_path = '/home/user/audit.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE raw_events (document TEXT)')

events = []

def add_tx(src, dst, amt, status="completed", type="transfer"):
    events.append({
        "payload": {
            "metadata": {"type": type, "status": status},
            "routing": {"sender_id": src, "receiver_id": dst},
            "financials": {"amount": amt}
        }
    })

# Add cycle: ACT_A -> ACT_B -> ACT_C -> ACT_A
add_tx("ACT_A", "ACT_B", 100)
add_tx("ACT_B", "ACT_C", 100)
add_tx("ACT_C", "ACT_A", 100)

# Make ACT_C the highest PageRank in the cycle by pointing many nodes to it
for i in range(1, 20):
    add_tx(f"NOISE_{i}", "ACT_C", 50)

# Add a separate node ACT_X with even higher PageRank but NOT in a cycle
for i in range(20, 50):
    add_tx(f"NOISE_{i}", "ACT_X", 50)

# Add some failed/pending transactions and non-transfers to test filtering
add_tx("ACT_C", "ACT_A", 100, status="pending")
add_tx("ACT_X", "ACT_A", 100, type="deposit")

for ev in events:
    c.execute('INSERT INTO raw_events (document) VALUES (?)', (json.dumps(ev),))

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user

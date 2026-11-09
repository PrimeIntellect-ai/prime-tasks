#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

# Set a fixed seed for reproducibility (optional but good practice)
random.seed(42)

conn = sqlite3.connect('/home/user/audit.db')
c = conn.cursor()

c.execute('CREATE TABLE communications (id INTEGER PRIMARY KEY, sender_id TEXT, receiver_id TEXT)')

# Create the index
c.execute('CREATE INDEX idx_sender ON communications(sender_id)')

edges = [
    ("EMP001", "EMP999"), ("EMP002", "EMP999"), ("EMP003", "EMP999"), 
    ("EMP004", "EMP999"), ("EMP005", "EMP999"), ("EMP006", "EMP999"),
    ("EMP007", "EMP999"), ("EMP008", "EMP999"), ("EMP009", "EMP999"),
    ("EMP010", "EMP888"), ("EMP011", "EMP888"), ("EMP012", "EMP888"),
    ("EMP013", "EMP888"), ("EMP014", "EMP888"), ("EMP015", "EMP777"),
    ("EMP016", "EMP777"), ("EMP017", "EMP777"), ("EMP018", "EMP111")
]

# Add some random noise
for i in range(20):
    edges.append((f"EMP{random.randint(100, 150)}", f"EMP{random.randint(200, 250)}"))

c.executemany('INSERT INTO communications (sender_id, receiver_id) VALUES (?, ?)', edges)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

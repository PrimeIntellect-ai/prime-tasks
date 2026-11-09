#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/audit.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

# Create schema
c.execute("""
CREATE TABLE nodes (
    node_id TEXT PRIMARY KEY,
    node_type TEXT,
    name TEXT
)
""")

c.execute("""
CREATE TABLE edges (
    source_id TEXT,
    target_id TEXT,
    rel_type TEXT,
    action_date DATE
)
""")

# Insert Nodes
nodes = [
    ("P1", "person", "Alice Smith"),
    ("P2", "person", "Bob Jones"),
    ("P3", "person", "Charlie Davis"),
    ("P4", "person", "Diana Prince"),
    ("C1", "company", "Shady Corp"),
    ("C2", "company", "Legit LLC"),
    ("A1", "account", "Offshore Trust X"),
    ("A2", "account", "Main Bank Acct")
]
c.executemany("INSERT INTO nodes VALUES (?, ?, ?)", nodes)

# Insert Edges
edges = [
    # Decoy 1: Chronology is wrong (pays happens before approves)
    ("P3", "P4", "emails", "2023-01-10"),
    ("P4", "C2", "approves", "2023-01-15"),
    ("C2", "A2", "pays", "2023-01-12"),
    ("P3", "A2", "owns", "2020-01-01"),

    # Decoy 2: Missing ownership
    ("P4", "P2", "emails", "2023-02-01"),
    ("P2", "C2", "approves", "2023-02-05"),
    ("C2", "A1", "pays", "2023-02-10"),

    # The actual kickback pattern 1
    ("P1", "P2", "emails", "2023-03-01"),
    ("P2", "C1", "approves", "2023-03-05"),
    ("C1", "A1", "pays", "2023-03-10"),
    ("P1", "A1", "owns", "2019-05-12"),

    # The actual kickback pattern 2 (to test sorting)
    ("P3", "P1", "emails", "2023-04-01"),
    ("P1", "C1", "approves", "2023-04-05"),
    ("C1", "A2", "pays", "2023-04-10"),
    ("P3", "A2", "owns", "2019-05-12")
]
c.executemany("INSERT INTO edges VALUES (?, ?, ?, ?)", edges)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py

    chmod -R 777 /home/user

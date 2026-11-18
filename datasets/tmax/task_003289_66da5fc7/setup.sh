#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import json

db_path = "/home/user/research_data.db"
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE papers (id TEXT, title TEXT, metadata_json TEXT)")
c.execute("CREATE TABLE citations (source_id TEXT, target_id TEXT)")

# Papers data: id, title, updated_at, categories
papers = [
    # Stale rows for P-START
    ("P-START", "Origin", 100, ["AI"]),
    ("P-START", "Origin Final", 200, ["AI", "ML"]), 

    # Valid intermediate nodes
    ("P-A", "Node A", 150, ["Graph", "Math"]),
    ("P-B", "Node B", 160, ["Math", "Optimization"]),
    ("P-C", "Node C", 170, ["AI", "Vision"]),

    # Stale rows for P-B
    ("P-B", "Node B Old", 50, ["Math"]),

    # Destination
    ("P-END", "Destination", 300, ["ML", "Systems"]),

    # Trap node
    ("P-TRAP", "Trap", 250, ["Magic"])
]

for pid, title, upd, cats in papers:
    meta = json.dumps({"updated_at": upd, "categories": cats})
    c.execute("INSERT INTO papers VALUES (?, ?, ?)", (pid, title, meta))

# Citations
citations = [
    ("P-START", "P-A"),
    ("P-START", "P-B"),
    ("P-START", "P-A"), # duplicate
    ("P-A", "P-C"),
    ("P-B", "P-C"),
    ("P-C", "P-END"),
    ("P-START", "P-TRAP"), # trap path
    ("P-TRAP", "P-END")
]

for src, tgt in citations:
    c.execute("INSERT INTO citations VALUES (?, ?)", (src, tgt))

conn.commit()
conn.close()
EOF

python3 /tmp/setup_db.py
rm /tmp/setup_db.py

chmod -R 777 /home/user

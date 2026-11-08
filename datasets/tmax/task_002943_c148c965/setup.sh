#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libsqlite3-dev sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import json
import os

db_path = "/home/user/papers.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute("""
CREATE TABLE papers (
    id INTEGER PRIMARY KEY,
    title TEXT,
    year INTEGER,
    metadata_json TEXT
)
""")

cursor.execute("""
CREATE TABLE citations (
    citing_id INTEGER,
    cited_id INTEGER
)
""")

domains = ["Computer Science", "Physics", "Biology", "Mathematics"]

# Generate 1000 papers
for i in range(1, 1001):
    domain = domains[i % 4]
    meta = json.dumps({"domain": domain, "keywords": ["data", "science"]})
    cursor.execute("INSERT INTO papers (id, title, year, metadata_json) VALUES (?, ?, ?, ?)", 
                   (i, f"Paper {i}", 2020 + (i % 4), meta))

# Generate citations for Paper 1
# Depth 1: 10 papers citing paper 1 (IDs 2-11)
for i in range(2, 12):
    cursor.execute("INSERT INTO citations (citing_id, cited_id) VALUES (?, ?)", (i, 1))

# Depth 2: 30 papers citing Depth 1 (IDs 12-41)
for i in range(12, 42):
    # Cite a pseudo-random depth 1 paper
    cited = 2 + (i % 10)
    cursor.execute("INSERT INTO citations (citing_id, cited_id) VALUES (?, ?)", (i, cited))

# Depth 3: 50 papers citing Depth 2 (IDs 42-91)
for i in range(42, 92):
    cited = 12 + (i % 30)
    cursor.execute("INSERT INTO citations (citing_id, cited_id) VALUES (?, ?)", (i, cited))

# Noise (other citations)
for i in range(100, 200):
    cursor.execute("INSERT INTO citations (citing_id, cited_id) VALUES (?, ?)", (i, i-10))

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user

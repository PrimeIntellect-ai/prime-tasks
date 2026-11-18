#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/citation_graph.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute("CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT)")
cursor.execute("CREATE TABLE citations (source_id INTEGER, target_id INTEGER)")

# Insert papers
for i in range(1, 51):
    cursor.execute("INSERT INTO papers (id, title) VALUES (?, ?)", (i, f"Paper {i}"))

# Clean edges
edges = [
    (1, 2), (2, 3), (3, 4), (4, 42),
    (10, 15), (15, 20), (20, 25), (25, 42),
    (10, 11), (11, 12), (12, 13), (13, 14), (14, 42),
    (1, 7), (2, 7), (3, 7), (4, 7), (5, 7), (6, 7), (8, 7), (9, 7), (11, 7), (12, 7),
    (1, 8), (2, 8), (3, 8), (4, 8), (5, 8)
]

# Add duplicates and self citations
dirty_edges = edges.copy()
dirty_edges.extend([
    (10, 15), (10, 15), (10, 15),
    (25, 42), (25, 42),
    (7, 7), (7, 7), (42, 42), (10, 10)
])

cursor.executemany("INSERT INTO citations (source_id, target_id) VALUES (?, ?)", dirty_edges)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user

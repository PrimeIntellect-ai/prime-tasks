#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/citation_graph.db')
c = conn.cursor()

c.execute('''CREATE TABLE papers (paper_id INTEGER PRIMARY KEY, title TEXT)''')
c.execute('''CREATE TABLE citations (source_id INTEGER, target_id INTEGER)''')

# Insert nodes
for i in range(1, 11):
    c.execute("INSERT INTO papers (paper_id, title) VALUES (?, ?)", (i, f"Paper {i}"))

# Insert edges
edges = [
    (1, 2), (1, 3), (1, 4), (1, 5), (1, 6),
    (2, 1), (2, 3), (2, 4), (2, 5),
    (3, 1), (3, 2), (3, 4), (3, 5), (3, 6), (3, 7), (3, 8),
    (4, 9), (5, 10), (6, 9)
]

for u, v in edges:
    c.execute("INSERT INTO citations (source_id, target_id) VALUES (?, ?)", (u, v))

# Insert duplicate edges (stale/corrupted data)
duplicates = [
    (1, 2), (1, 2), (3, 4), (3, 4), (3, 4), (2, 5)
]
for u, v in duplicates:
    c.execute("INSERT INTO citations (source_id, target_id) VALUES (?, ?)", (u, v))

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user

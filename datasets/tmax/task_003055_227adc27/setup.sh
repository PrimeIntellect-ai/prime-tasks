#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/graph_data

    cat << 'EOF' > /tmp/setup_env.py
import sqlite3
import csv
import os

db_path = '/home/user/graph_data/knowledge.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute('''CREATE TABLE nodes (id TEXT PRIMARY KEY, type TEXT, properties_json TEXT)''')
cur.execute('''CREATE TABLE edges (source TEXT, target TEXT, weight REAL, updated_at INTEGER)''')

# Insert Nodes
nodes = [(f'N_{i}', 'concept', '{}') for i in range(10)]
nodes.append(('ROOT_42', 'concept', '{}'))
cur.executemany("INSERT INTO nodes VALUES (?, ?, ?)", nodes)

# Insert Edges with STALE ROWS
edges = [
    ('ROOT_42', 'N_1', 1.0, 100),
    ('ROOT_42', 'N_1', 1.5, 50), # Stale
    ('ROOT_42', 'N_2', 1.0, 100),
    ('N_1', 'N_3', 1.0, 100),
    ('N_1', 'N_3', 2.0, 150), # Valid, 100 is stale
    ('N_3', 'N_4', 1.0, 100),
    ('N_2', 'N_5', 1.0, 100)
]
cur.executemany("INSERT INTO edges VALUES (?, ?, ?, ?)", edges)
conn.commit()
conn.close()

# Create updates CSV
csv_path = '/home/user/graph_data/new_edges.csv'
with open(csv_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['source', 'target', 'weight', 'updated_at'])
    writer.writerow(['ROOT_42', 'N_2', 3.0, 200]) # Should update
    writer.writerow(['N_4', 'N_6', 1.0, 300]) # New edge
    writer.writerow(['N_1', 'N_3', 0.5, 80]) # Should NOT update (stale update)
    writer.writerow(['N_5', 'ROOT_42', 1.0, 100]) # Loop back

EOF
    python3 /tmp/setup_env.py
    rm /tmp/setup_env.py

    chmod -R 777 /home/user

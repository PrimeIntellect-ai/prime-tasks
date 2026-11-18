#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3
import random

random.seed(42)

conn = sqlite3.connect('/home/user/graph.db')
c = conn.cursor()

c.execute('CREATE TABLE nodes (id INTEGER PRIMARY KEY, type TEXT)')
c.execute('CREATE TABLE edges (src INTEGER, dst INTEGER)')

types = ['A', 'B', 'C', 'D']
nodes = [(i, types[i % 4]) for i in range(1, 101)]
c.executemany('INSERT INTO nodes VALUES (?, ?)', nodes)

edges = []
for _ in range(300):
    src = random.randint(1, 100)
    dst = random.randint(1, 100)
    if src != dst:
        edges.append((src, dst))

c.executemany('INSERT INTO edges VALUES (?, ?)', edges)

conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    cat << 'EOF' > /home/user/analyze.py
import sqlite3
import json

def run_analysis():
    conn = sqlite3.connect('/home/user/graph.db')
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # Buggy query with implicit cross join
    query = """
    WITH TwoHop AS (
        SELECT n.type, n.id as src_id, n2.id as dst_id
        FROM nodes n
        JOIN edges e1 ON n.id = e1.src
        JOIN edges e2 ON e1.dst = e2.src
        JOIN nodes n2 ON n.type = n2.type -- BUG: implicit cross join instead of e2.dst = n2.id
    ),
    Aggregated AS (
        SELECT type, src_id as id, COUNT(DISTINCT dst_id) as ext_degree
        FROM TwoHop
        GROUP BY type, src_id
    )
    SELECT type, id, ext_degree,
           RANK() OVER(PARTITION BY type ORDER BY ext_degree DESC, id ASC) as rnk
    FROM Aggregated
    """

    c.execute(query)
    results = [dict(row) for row in c.fetchall()]

    # Filter for rnk == 1 and write to JSON
    # ... (To be implemented by the user)

if __name__ == "__main__":
    run_analysis()
EOF

    chmod -R 777 /home/user

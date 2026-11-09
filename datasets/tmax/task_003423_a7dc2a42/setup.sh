#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import os

db_path = '/home/user/network.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE nodes (id TEXT PRIMARY KEY, region TEXT)''')
c.execute('''CREATE TABLE edges (source TEXT, target TEXT, weight REAL)''')

nodes = [
    ('n1', 'us-east'), ('n2', 'us-east'), ('n3', 'us-east'), ('n4', 'us-east'), ('n5', 'us-east'),
    ('n6', 'eu-west'), ('n7', 'eu-west'), ('n8', 'eu-west')
]
edges = [
    ('n1', 'n2', 1.5), ('n3', 'n2', 2.0), ('n4', 'n2', 0.5), ('n5', 'n2', 1.0),
    ('n2', 'n1', 1.0), ('n1', 'n3', 0.8),
    ('n6', 'n7', 1.0), ('n7', 'n8', 1.2)
]

c.executemany("INSERT INTO nodes VALUES (?, ?)", nodes)
c.executemany("INSERT INTO edges VALUES (?, ?, ?)", edges)
conn.commit()
conn.close()

buggy_script = """import sqlite3
import sys

def analyze(region):
    conn = sqlite3.connect('/home/user/network.db')
    c = conn.cursor()

    # BAD SQL: Implicit cross join and SQL injection vulnerability
    query = f"SELECT e.source, e.target, e.weight FROM edges e, nodes n WHERE n.region = '{region}'"
    c.execute(query)
    rows = c.fetchall()

    # TODO: Build graph, calculate in-degree centrality, and export top 3 to CSV

    conn.close()

if __name__ == '__main__':
    if len(sys.argv) > 1:
        analyze(sys.argv[1])
"""

with open('/home/user/analyze_network.py', 'w') as f:
    f.write(buggy_script)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

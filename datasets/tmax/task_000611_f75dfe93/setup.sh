#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import sqlite3
import random

os.makedirs('/home/user', exist_ok=True)

# Generate graph.db
random.seed(42)
conn = sqlite3.connect('/home/user/graph.db')
conn.execute("CREATE TABLE edges (source INTEGER, target INTEGER)")

edges = set()
# Create a dense graph to ensure triangles exist
for _ in range(2000):
    u = random.randint(1, 50)
    v = random.randint(1, 50)
    if u != v:
        edges.add((u, v))

conn.executemany("INSERT INTO edges VALUES (?, ?)", list(edges))
conn.commit()
conn.close()

# Create buggy analyze_graph.py
buggy_script = """import sqlite3

def count_triangles():
    conn = sqlite3.connect('/home/user/graph.db')
    cursor = conn.cursor()
    # BUG: Missing e3.target = e1.source condition
    query = '''
        SELECT COUNT(*) 
        FROM edges e1
        JOIN edges e2 ON e1.target = e2.source
        JOIN edges e3 ON e2.target = e3.source
    '''
    cursor.execute(query)
    count = cursor.fetchone()[0]
    print(f"Triangles found: {count}")
    return count

if __name__ == "__main__":
    count_triangles()
"""
with open('/home/user/analyze_graph.py', 'w') as f:
    f.write(buggy_script)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

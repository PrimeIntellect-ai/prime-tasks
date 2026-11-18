#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import random

conn = sqlite3.connect('/home/user/research_data.db')
c = conn.cursor()
c.execute('CREATE TABLE artifacts (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE relationships (source_id INTEGER, target_id INTEGER)')

# Insert artifacts
artifacts = [(1, 'Alpha'), (1000, 'Omega')]
for i in range(2, 1000):
    artifacts.append((i, f'Node_{i}'))

c.executemany('INSERT INTO artifacts VALUES (?, ?)', artifacts)

# Insert relationships
edges = []
# Create a valid path of length 6: Alpha(1) -> 10 -> 20 -> 30 -> 40 -> 50 -> Omega(1000)
path = [1, 10, 20, 30, 40, 50, 1000]
for i in range(len(path)-1):
    edges.append((path[i], path[i+1]))

# Add noise and cycles
random.seed(42)
for _ in range(5000):
    u = random.randint(1, 999)
    v = random.randint(1, 999)
    if u != v:
        edges.append((u, v))

c.executemany('INSERT INTO relationships VALUES (?, ?)', edges)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup.py

    cat << 'EOF' > /home/user/find_path.py
import sqlite3

def find_shortest_path():
    conn = sqlite3.connect('/home/user/research_data.db')
    c = conn.cursor()

    # Buggy query with implicit cross join / missing join condition
    query = """
    WITH RECURSIVE
      search_graph(id, depth) AS (
        SELECT id, 0 FROM artifacts WHERE name = 'Alpha'
        UNION ALL
        SELECT r.target_id, sg.depth + 1
        FROM search_graph sg, relationships r
        -- Missing join condition: WHERE sg.id = r.source_id
        WHERE sg.depth < 10
      )
    SELECT min(depth) FROM search_graph sg
    JOIN artifacts a ON sg.id = a.id
    WHERE a.name = 'Omega';
    """

    try:
        c.execute(query)
        result = c.fetchone()[0]
        with open('/home/user/result.txt', 'w') as f:
            f.write(str(result))
    except Exception as e:
        print("Error:", e)

find_shortest_path()
EOF

    chmod -R 777 /home/user

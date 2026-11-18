#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak sqlite3
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/alert.wav "Critical failure detected. Hardware destroyed. Do not route traffic through NodeDelta, NodeSigma, or NodeTau. Acknowledge."

    # Create the database setup script
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

conn = sqlite3.connect('/app/routing_backup.db')
c = conn.cursor()
c.execute("CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT)")
c.execute("CREATE TABLE edges (source_id INTEGER, target_id INTEGER, weight INTEGER)")

nodes = ['NodeAlpha', 'NodeBeta', 'NodeGamma', 'NodeDelta', 'NodeSigma', 'NodeTau', 'NodeOmega', 'NodeZeta', 'NodeEta', 'NodeTheta', 'NodeIota', 'NodeKappa', 'NodeLambda', 'NodeMu', 'NodeNu', 'NodeXi', 'NodeOmicron', 'NodePi', 'NodeRho', 'NodeUpsilon']
for i, n in enumerate(nodes):
    c.execute("INSERT INTO nodes (id, name) VALUES (?, ?)", (i+1, n))

random.seed(42)
for i in range(1, len(nodes)+1):
    for j in range(1, len(nodes)+1):
        if i != j and random.random() > 0.7:
            c.execute("INSERT INTO edges (source_id, target_id, weight) VALUES (?, ?, ?)", (i, j, random.randint(1, 10)))

c.execute("CREATE INDEX idx_edges_source ON edges(source_id)")
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py

    # Create the oracle script
    cat << 'EOF' > /app/oracle_route_calculator.py
import sys
import sqlite3
import heapq

def get_shortest_path(start, end):
    conn = sqlite3.connect('/app/routing_backup.db')
    c = conn.cursor()

    c.execute("SELECT id, name FROM nodes")
    nodes = {row[1]: row[0] for row in c.fetchall()}

    if start not in nodes or end not in nodes:
        return -1

    start_id = nodes[start]
    end_id = nodes[end]

    bad_nodes = {'NodeDelta', 'NodeSigma', 'NodeTau'}
    bad_ids = {nodes[n] for n in bad_nodes if n in nodes}

    c.execute("SELECT source_id, target_id, weight FROM edges NOT INDEXED")
    graph = {}
    for src, tgt, w in c.fetchall():
        if src in bad_ids or tgt in bad_ids:
            continue
        if src not in graph:
            graph[src] = []
        graph[src].append((tgt, w))

    pq = [(0, start_id)]
    dist = {start_id: 0}

    while pq:
        d, u = heapq.heappop(pq)

        if d > dist.get(u, float('inf')):
            continue

        if u == end_id:
            return d

        for v, w in graph.get(u, []):
            if dist.get(v, float('inf')) > d + w:
                dist[v] = d + w
                heapq.heappush(pq, (dist[v], v))

    return -1

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(1)
    print(get_shortest_path(sys.argv[1], sys.argv[2]))
EOF

    chmod +x /app/oracle_route_calculator.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

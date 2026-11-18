#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget curl tar sqlite3
    pip3 install pytest networkx==3.1

    mkdir -p /home/user/data
    mkdir -p /app
    mkdir -p /opt/oracle

    # Download and extract networkx source
    cd /app
    pip3 download --no-deps --no-binary :all: networkx==3.1
    tar -xzf networkx-3.1.tar.gz
    rm networkx-3.1.tar.gz

    # Inject perturbation
    sed -i '/def bidirectional_shortest_path(G, source, target):/a \    if True:\n        raise Exception("DBA Optimization Required")' /app/networkx-3.1/networkx/algorithms/shortest_paths/unweighted.py

    # Generate the database
    cat << 'EOF' > /tmp/generate_db.py
import sqlite3
import random

random.seed(42)
conn = sqlite3.connect('/home/user/data/network.db')
c = conn.cursor()
c.execute('CREATE TABLE nodes (id INTEGER PRIMARY KEY, weight INTEGER, is_active BOOLEAN)')
c.execute('CREATE TABLE edges (source INTEGER, target INTEGER, is_active BOOLEAN)')

nodes = list(range(1, 1001))
for i in nodes:
    weight = random.randint(1, 100)
    is_active = 1 if random.random() > 0.1 else 0
    c.execute('INSERT INTO nodes VALUES (?, ?, ?)', (i, weight, is_active))

# Create a connected graph base
for i in range(2, 1001):
    source = random.choice(nodes[:i-1])
    target = i
    is_active = 1 if random.random() > 0.1 else 0
    c.execute('INSERT INTO edges VALUES (?, ?, ?)', (source, target, is_active))

# Add random edges
for _ in range(3000):
    source = random.choice(nodes)
    target = random.choice(nodes)
    if source != target:
        is_active = 1 if random.random() > 0.1 else 0
        c.execute('INSERT INTO edges VALUES (?, ?, ?)', (source, target, is_active))

conn.commit()
conn.close()
EOF
    python3 /tmp/generate_db.py
    rm /tmp/generate_db.py

    # Create oracle script
    cat << 'EOF' > /opt/oracle/reference_graph_query.py
import sys
import sqlite3
import networkx as nx

def main():
    conn = sqlite3.connect('/home/user/data/network.db')
    c = conn.cursor()

    # Load active nodes
    c.execute('SELECT id, weight FROM nodes WHERE is_active=1')
    active_nodes = {row[0]: row[1] for row in c.fetchall()}

    # Load active edges between active nodes
    c.execute('SELECT source, target FROM edges WHERE is_active=1')
    active_edges = []
    for row in c.fetchall():
        u, v = row[0], row[1]
        if u in active_nodes and v in active_nodes:
            active_edges.append((u, v))

    G = nx.Graph()
    for n in active_nodes:
        G.add_node(n, weight=active_nodes[n])
    G.add_edges_from(active_edges)

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            start, end = map(int, line.split(','))
            if start not in G or end not in G:
                print("-1,-1")
                continue
            path = nx.shortest_path(G, source=start, target=end)
            path_length = len(path) - 1
            total_weight = sum(G.nodes[n]['weight'] for n in path)
            print(f"{path_length},{total_weight}")
        except (nx.NetworkXNoPath, nx.NodeNotFound):
            print("-1,-1")

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user

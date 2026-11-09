#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random
from collections import defaultdict, deque

def setup_db():
    random.seed(12345)

    conn = sqlite3.connect('/home/user/backup_deps.db')
    c = conn.cursor()

    c.execute('CREATE TABLE databases (id INTEGER PRIMARY KEY, name TEXT, backup_time INTEGER)')
    c.execute('CREATE TABLE dependencies (source_id INTEGER, target_id INTEGER)')

    num_nodes = 5000
    num_edges = 15000

    # Generate nodes
    nodes = []
    backup_times = {}
    for i in range(num_nodes):
        name = f"db_{i}"
        bt = random.randint(5, 120)
        nodes.append((i, name, bt))
        backup_times[i] = bt

    c.executemany('INSERT INTO databases VALUES (?, ?, ?)', nodes)

    # Generate DAG edges (i < j ensures no cycles)
    edges = set()
    adj = defaultdict(list)
    in_degree = defaultdict(int)

    while len(edges) < num_edges:
        u = random.randint(0, num_nodes - 2)
        v = random.randint(u + 1, num_nodes - 1)
        if (u, v) not in edges:
            edges.add((u, v))
            adj[u].append(v)
            in_degree[v] += 1

    c.executemany('INSERT INTO dependencies VALUES (?, ?)', list(edges))
    conn.commit()
    conn.close()

    # Compute Ground Truth
    # topological sort
    topo_order = []
    q = deque([i for i in range(num_nodes) if in_degree[i] == 0])

    while q:
        curr = q.popleft()
        topo_order.append(curr)
        for nxt in adj[curr]:
            in_degree[nxt] -= 1
            if in_degree[nxt] == 0:
                q.append(nxt)

    # Longest path distances
    dist = {i: backup_times[i] for i in range(num_nodes)}
    parent = {i: -1 for i in range(num_nodes)}

    for u in topo_order:
        for v in adj[u]:
            if dist[u] + backup_times[v] > dist[v]:
                dist[v] = dist[u] + backup_times[v]
                parent[v] = u

    # Find max distance
    max_dist = 0
    end_node = -1
    for i in range(num_nodes):
        if dist[i] > max_dist:
            max_dist = dist[i]
            end_node = i

    # Reconstruct path
    path = []
    curr = end_node
    while curr != -1:
        path.append(curr)
        curr = parent[curr]
    path.reverse()

    path_names = [f"db_{i}" for i in path]

    # Write truth files for verification (hidden from agent)
    with open('/tmp/truth_time.txt', 'w') as f:
        f.write(str(max_dist))
    with open('/tmp/truth_sequence.txt', 'w') as f:
        f.write(",".join(path_names))

if __name__ == '__main__':
    setup_db()
EOF

    python3 /tmp/setup_db.py
    chmod -R 777 /home/user

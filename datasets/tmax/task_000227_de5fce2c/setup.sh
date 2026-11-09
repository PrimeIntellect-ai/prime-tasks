#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 binutils
    pip3 install pytest networkx pandas scikit-learn pyinstaller

    mkdir -p /app
    cd /app

    # Create the Python script that will be compiled into the oracle binary
    cat << 'EOF' > /app/compute_relevance.py
import sys
import sqlite3
import heapq

def get_score(src, dst):
    conn = sqlite3.connect('/app/datasets.db')
    c = conn.cursor()
    c.execute('SELECT src, dst, cost FROM ds_links')
    graph = {}
    for u, v, cost in c.fetchall():
        if u not in graph:
            graph[u] = []
        graph[u].append((v, cost))
    conn.close()

    pq = [(0.0, src)]
    visited = set()
    distances = {src: 0.0}

    while pq:
        dist, node = heapq.heappop(pq)
        if node == dst:
            return 1.0 / (1.0 + dist)
        if node in visited:
            continue
        visited.add(node)
        for neighbor, weight in graph.get(node, []):
            if neighbor not in visited:
                new_dist = dist + weight
                if new_dist < distances.get(neighbor, float('inf')):
                    distances[neighbor] = new_dist
                    heapq.heappush(pq, (new_dist, neighbor))
    return 0.0

if __name__ == '__main__':
    if len(sys.argv) == 3:
        src = int(sys.argv[1])
        dst = int(sys.argv[2])
        print(f"{get_score(src, dst):.4f}")
EOF

    # Compile the oracle binary and strip it
    pyinstaller --onefile compute_relevance.py
    cp dist/compute_relevance /app/compute_relevance
    strip -s /app/compute_relevance
    chmod +x /app/compute_relevance
    rm -rf build dist compute_relevance.spec compute_relevance.py

    # Generate the database and the hidden test pairs/scores
    cat << 'EOF' > /app/generate_db.py
import sqlite3
import random
import networkx as nx

conn = sqlite3.connect('/app/datasets.db')
c = conn.cursor()
c.execute('CREATE TABLE ds_entities (id INTEGER PRIMARY KEY, category TEXT)')
c.execute('CREATE TABLE ds_links (src INTEGER, dst INTEGER, cost REAL)')

G = nx.erdos_renyi_graph(100, 0.1, directed=True, seed=42)
for i in G.nodes():
    c.execute('INSERT INTO ds_entities (id, category) VALUES (?, ?)', (i, 'catA'))

random.seed(42)
for u, v in G.edges():
    cost = random.uniform(0.1, 5.0)
    c.execute('INSERT INTO ds_links (src, dst, cost) VALUES (?, ?, ?)', (u, v, cost))
    G[u][v]['cost'] = cost

conn.commit()
conn.close()

pairs = []
for _ in range(1000):
    u, v = random.sample(list(G.nodes()), 2)
    pairs.append((u, v))

with open('/app/hidden_test_pairs.csv', 'w') as f_pairs, open('/app/hidden_expected_scores.csv', 'w') as f_scores:
    for u, v in pairs:
        try:
            length = nx.shortest_path_length(G, u, v, weight='cost')
            score = 1.0 / (1.0 + length)
        except nx.NetworkXNoPath:
            score = 0.0
        f_pairs.write(f"{u},{v}\n")
        f_scores.write(f"{u},{v},{score:.4f}\n")
EOF

    python3 /app/generate_db.py
    rm /app/generate_db.py

    # Create the verification script
    cat << 'EOF' > /app/verify.py
import sys
import pandas as pd
from sklearn.metrics import mean_squared_error
import subprocess

# Run agent's script
subprocess.run(["python3", "/home/user/batch_score.py", "/app/hidden_test_pairs.csv", "/home/user/predictions.csv"], check=True)

# Load predictions and ground truth
try:
    preds = pd.read_csv("/home/user/predictions.csv", header=None, names=["A", "B", "score"])
    truth = pd.read_csv("/app/hidden_expected_scores.csv", header=None, names=["A", "B", "score"])

    # Merge to ensure alignment
    merged = pd.merge(truth, preds, on=["A", "B"], suffixes=("_true", "_pred"))
    mse = mean_squared_error(merged["score_true"], merged["score_pred"])

    print(f"MSE: {mse:.6f}")
    if mse < 0.001:
        print("PASS")
        sys.exit(0)
    else:
        print("FAIL")
        sys.exit(1)
except Exception as e:
    print(f"FAIL: {e}")
    sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

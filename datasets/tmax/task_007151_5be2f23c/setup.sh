#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import csv
import random

random.seed(123)
nodes = list(range(100))
edges = []

# Create a graph that has paths from 0 to 99
for i in range(99):
    edges.append((i, i+1, random.randint(1, 10)))

# Add some random edges
for _ in range(200):
    u = random.randint(0, 99)
    v = random.randint(0, 99)
    if u != v:
        edges.append((u, v, random.randint(0, 5)))

with open('/home/user/network_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['source', 'target', 'observations'])
    for u, v, obs in edges:
        writer.writerow([u, v, obs])

slow_sim_code = """import csv
import random
from collections import deque
import copy

def load_graph(filename):
    graph = {}
    with open(filename, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            u, v, obs = int(row['source']), int(row['target']), int(row['observations'])
            p = 1.0 / (1.0 + obs)
            if u not in graph: graph[u] = []
            if v not in graph: graph[v] = []
            graph[u].append((v, p))
            graph[v].append((u, p))
    return graph

def has_path(graph, start, end):
    if start not in graph: return False
    visited = set([start])
    queue = deque([start])
    while queue:
        node = queue.popleft()
        if node == end:
            return True
        for neighbor in graph.get(node, []):
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append(neighbor)
    return False

def run_simulation():
    random.seed(42)
    graph = load_graph('/home/user/network_data.csv')
    iterations = 10000
    success_count = 0

    for _ in range(iterations):
        # Extremely slow: deepcopy and element-by-element iteration
        sim_graph = {}
        for u, neighbors in graph.items():
            sim_graph[u] = []
            for v, p in neighbors:
                if random.random() > p:  # edge survives
                    sim_graph[u].append(v)

        if has_path(sim_graph, 0, 99):
            success_count += 1

    return success_count / iterations

if __name__ == '__main__':
    prob = run_simulation()
    with open('/home/user/result.txt', 'w') as f:
        f.write(str(prob))
"""

with open('/home/user/slow_sim.py', 'w') as f:
    f.write(slow_sim_code)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

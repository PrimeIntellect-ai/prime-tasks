#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest numpy scipy

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > ppi_network.csv
A,B
A,C
A,D
A,E
B,C
C,D
D,E
E,F
F,G
G,A
A,F
B,G
C,F
D,G
EOF

    cat << 'EOF' > simulate_diffusion.py
import sys
import json
import numpy as np

def load_graph(filename):
    graph = {}
    with open(filename) as f:
        for line in f:
            u, v = line.strip().split(',')
            if u not in graph: graph[u] = set()
            if v not in graph: graph[v] = set()
            graph[u].add(v)
            graph[v].add(u)
    return graph

def simulate(graph_file, iterations=10):
    graph = load_graph(graph_file)
    nodes = sorted(list(graph.keys()))

    # Initialize distribution
    dist = {n: np.float32(1.0 / len(nodes)) for n in nodes}

    for _ in range(iterations):
        new_dist = {}
        for n in nodes:
            # Bug: iteration over a set yields different orders across runs.
            # We use float32 and inject large numbers to force catastrophic cancellation
            # and amplify the associative differences of floating point math.
            val = np.float32(0.0)
            for nbr in graph[n]:
                # amplify order difference
                val = np.float32(val + np.float32(1e6))
                val = np.float32(val + dist[nbr])
                val = np.float32(val - np.float32(1e6))
            new_dist[n] = val

        # Normalize
        total = sum(new_dist.values())
        if total > 0:
            dist = {n: new_dist[n] / total for n in nodes}
        else:
            dist = new_dist

    # Convert float32 to float for json serialization
    return {k: float(v) for k, v in dist.items()}

if __name__ == "__main__":
    d = simulate("ppi_network.csv")
    print(json.dumps(d))
EOF

    chmod +x simulate_diffusion.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

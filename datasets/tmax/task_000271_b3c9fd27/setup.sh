#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest pandas numpy

    mkdir -p /app
    mkdir -p /home/user

    # Generate the graph data and golden PageRank
    cat << 'EOF' > /app/generate_graph.py
import struct
import random

N = 10000
num_edges = 50000

out_degree = [0] * N
adj = [[] for _ in range(N)]
edges = []

random.seed(42)
for _ in range(num_edges):
    u = random.randint(0, N-1)
    v = random.randint(0, N-1)
    edges.append((u, v))
    out_degree[u] += 1
    adj[u].append(v)

with open('/app/backup.dat', 'wb') as f:
    for u, v in edges:
        f.write(struct.pack('ii', u, v))

pr = [1.0 / N] * N
d = 0.85

for _ in range(20):
    new_pr = [0.0] * N
    dangling_sum = 0.0
    for i in range(N):
        if out_degree[i] == 0:
            dangling_sum += pr[i]

    for u in range(N):
        if out_degree[u] > 0:
            share = pr[u] / out_degree[u]
            for v in adj[u]:
                new_pr[v] += share

    for i in range(N):
        new_pr[i] = d * new_pr[i] + d * (dangling_sum / N) + (1.0 - d) / N

    pr = new_pr

with open('/app/golden_pagerank.csv', 'w') as f:
    f.write("NodeID,PageRank\n")
    for i in range(N):
        f.write(f"{i},{pr[i]:.6f}\n")
EOF

    python3 /app/generate_graph.py

    # Create the graph_engine C++ source
    cat << 'EOF' > /app/graph_engine.cpp
#include <iostream>
#include <fstream>
#include <cstdlib>

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    int query_u = std::atoi(argv[1]);
    std::ifstream fin("/app/backup.dat", std::ios::binary);
    if (!fin) return 1;
    int u, v;
    while (fin.read(reinterpret_cast<char*>(&u), sizeof(u)) && fin.read(reinterpret_cast<char*>(&v), sizeof(v))) {
        if (u == query_u) {
            std::cout << v << "\n";
        }
    }
    return 0;
}
EOF

    g++ -O3 /app/graph_engine.cpp -o /app/graph_engine
    strip /app/graph_engine
    rm /app/graph_engine.cpp /app/generate_graph.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

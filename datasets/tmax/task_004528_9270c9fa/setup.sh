#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest

    mkdir -p /app/graphetl-lib/graphetl
    mkdir -p /app/data

    cat << 'EOF' > /app/graphetl-lib/graphetl/__init__.py
from .graph import Graph
EOF

    cat << 'EOF' > /app/graphetl-lib/graphetl/graph.py
import threading
from collections import defaultdict

class Graph:
    def __init__(self):
        self.adj = defaultdict(set)
        self.locks = defaultdict(threading.Lock)
        self.global_lock = threading.Lock()

    def get_node_lock(self, node):
        with self.global_lock:
            return self.locks[node]

    def add_edge(self, u, v):
        with self.get_node_lock(u):
            with self.get_node_lock(v):
                self.adj[u].add(v)
                self.adj[v].add(u)
EOF

    cat << 'EOF' > /app/data/transactions.csv
source,target
CUST_739,CUST_102
CUST_102,CUST_555
CUST_555,CUST_882
CUST_111,CUST_222
CUST_102,CUST_111
EOF

    cat << 'EOF' > /app/verifier_benchmark.py
import sys
import time
import threading
import random

sys.path.insert(0, '/app/graphetl-lib')
from graphetl import Graph

def worker(g, edges):
    for u, v in edges:
        if u != v:
            g.add_edge(u, v)

def main():
    g = Graph()
    threads = []
    edges_per_thread = 5000
    num_threads = 10

    nodes = [f"N_{i}" for i in range(100)]
    random.seed(42)

    for _ in range(num_threads):
        edges = [(random.choice(nodes), random.choice(nodes)) for _ in range(edges_per_thread)]
        t = threading.Thread(target=worker, args=(g, edges))
        threads.append(t)

    start_time = time.time()
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=10)
        if t.is_alive():
            print(0)
            sys.exit(0)

    elapsed = time.time() - start_time
    total_edges = num_threads * edges_per_thread
    throughput = total_edges / elapsed if elapsed > 0 else 0
    print(throughput)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

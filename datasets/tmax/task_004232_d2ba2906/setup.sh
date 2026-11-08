#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/kg_engine/src

    cat << 'EOF' > /home/user/generate_graph.py
import random
import csv

random.seed(42)
num_nodes = 5000
num_edges = 20000

edges = set()
while len(edges) < num_edges:
    u = random.randint(1, num_nodes)
    v = random.randint(1, num_nodes)
    if u != v:
        edges.add((u, v))

# Plant specific triangles to ensure predictability
# Triangle 1: 10 -> 20 -> 30 -> 10
edges.add((10, 20))
edges.add((20, 30))
edges.add((30, 10))

# Triangle 2: 99 -> 100 -> 101 -> 99
edges.add((99, 100))
edges.add((100, 101))
edges.add((101, 99))

# Boost the out-degree of node 20 to be the highest (it's in a triangle)
for i in range(100):
    edges.add((20, 10000 + i))

# Boost node 99 to be the second highest
for i in range(80):
    edges.add((99, 20000 + i))

# Boost node 10 to be the third highest
for i in range(60):
    edges.add((10, 30000 + i))

# Boost node 30 to be the fourth highest
for i in range(40):
    edges.add((30, 40000 + i))

# Boost node 100 to be the fifth highest
for i in range(20):
    edges.add((100, 50000 + i))

edges = list(edges)
random.shuffle(edges)

with open('/home/user/data/edges.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['source', 'target'])
    writer.writerows(edges)
EOF

    python3 /home/user/generate_graph.py

    cat << 'EOF' > /home/user/kg_engine/Cargo.toml
[package]
name = "kg_engine"
version = "0.1.0"
edition = "2021"

[dependencies]
csv = "1.2"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/kg_engine/src/main.rs
use std::fs::File;
use std::io::Write;

fn main() {
    println!("Please implement the optimized graph query engine.");
}
EOF

    chmod -R 777 /home/user

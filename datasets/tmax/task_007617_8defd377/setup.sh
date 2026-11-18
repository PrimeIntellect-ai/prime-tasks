#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

os.makedirs('/home/user', exist_ok=True)

# Set random seed for reproducibility
np.random.seed(42)

num_nodes = 100
num_steps = 1000
dt = 0.01
t = np.arange(num_steps) * dt

# Initialize arrays
data = np.zeros((num_nodes, num_steps))
frequencies = np.random.uniform(5, 45, num_nodes)

# Override frequencies for clusters
cluster1 = list(range(10, 31)) # 21 nodes
cluster2 = list(range(50, 86)) # 36 nodes, LARGEST CLUSTER

frequencies[cluster1] = 15.0
frequencies[cluster2] = 30.0

# Generate signals with some noise
for i in range(num_nodes):
    data[i] = np.sin(2 * np.pi * frequencies[i] * t) + 0.5 * np.random.randn(num_steps)

# Save numpy array
np.save('/home/user/simulation_data.npy', data)

# Generate network topology
edges = []

# Connect cluster 1 internally (random tree + extra edges to ensure connectivity)
for i in range(len(cluster1) - 1):
    edges.append((cluster1[i], cluster1[i+1]))
for _ in range(30):
    u, v = np.random.choice(cluster1, 2, replace=False)
    edges.append((u, v))

# Connect cluster 2 internally
for i in range(len(cluster2) - 1):
    edges.append((cluster2[i], cluster2[i+1]))
for _ in range(60):
    u, v = np.random.choice(cluster2, 2, replace=False)
    edges.append((u, v))

# Add random edges across the whole network (these won't pass the frequency filter)
for _ in range(150):
    u, v = np.random.choice(num_nodes, 2, replace=False)
    edges.append((u, v))

# Save edges
with open('/home/user/network_topology.txt', 'w') as f:
    for u, v in set(edges):
        f.write(f"{u} {v}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

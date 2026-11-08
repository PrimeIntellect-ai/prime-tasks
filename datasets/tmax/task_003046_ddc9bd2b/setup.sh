#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/data /home/user/src /home/user/output

    cat << 'EOF' > /tmp/setup.py
import os
import random
import ctypes
import math

# Create directories
os.makedirs("/home/user/data", exist_ok=True)
os.makedirs("/home/user/src", exist_ok=True)
os.makedirs("/home/user/output", exist_ok=True)

# Generate vectors.csv
random.seed(42)
with open("/home/user/data/vectors.csv", "w") as f:
    for i in range(1, 101):
        v = [random.uniform(-10.0, 10.0) for _ in range(5)]
        f.write(f"{i},{v[0]:.4f},{v[1]:.4f},{v[2]:.4f},{v[3]:.4f},{v[4]:.4f}\n")

# Compute ground truth
libc = ctypes.CDLL("libc.so.6")
libc.srand(2024)

# Generate matrix M (5x2)
M = [[0.0, 0.0] for _ in range(5)]
for i in range(5):
    for j in range(2):
        M[i][j] = (libc.rand() % 1000) / 1000.0

# Read vectors
vectors = {}
with open("/home/user/data/vectors.csv", "r") as f:
    for line in f:
        parts = line.strip().split(',')
        vec_id = int(parts[0])
        vec_vals = [float(x) for x in parts[1:]]
        vectors[vec_id] = vec_vals

# Project vectors
projected = {}
for vec_id, vec in vectors.items():
    p0 = sum(vec[k] * M[k][0] for k in range(5))
    p1 = sum(vec[k] * M[k][1] for k in range(5))
    projected[vec_id] = (p0, p1)

# Calculate distances to id=42
target_p = projected[42]
distances = []
for vec_id, p in projected.items():
    if vec_id == 42:
        continue
    dist = math.sqrt((p[0] - target_p[0])**2 + (p[1] - target_p[1])**2)
    distances.append((vec_id, dist))

# Sort by distance, then id
distances.sort(key=lambda x: (x[1], x[0]))

# Save ground truth for comparison
with open("/home/user/expected_recommendations.txt", "w") as f:
    for i in range(3):
        f.write(f"{distances[i][0]},{distances[i][1]:.4f}\n")
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

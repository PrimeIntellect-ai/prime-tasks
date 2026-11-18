#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import random
import math

random.seed(42)
N = 100
edges = set()
for i in range(N):
    edges.add((min(i, (i+1)%N), max(i, (i+1)%N)))
    edges.add((min(i, (i+2)%N), max(i, (i+2)%N)))

for _ in range(50):
    u = random.randint(0, N-1)
    v = random.randint(0, N-1)
    if u != v:
        edges.add((min(u,v), max(u,v)))

with open('/home/user/molecule.edgelist', 'w') as f:
    for u, v in edges:
        f.write(f"{u} {v}\n")
EOF
    python3 /tmp/setup.py

    chmod -R 777 /home/user

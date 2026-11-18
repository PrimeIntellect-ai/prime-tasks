#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/gen_data.py
import os
import random

random.seed(42)
num_nodes = 1000
num_edges = 5000

edges = set()
while len(edges) < num_edges:
    u = random.randint(1, num_nodes)
    v = random.randint(1, num_nodes)
    if u != v:
        edges.add(tuple(sorted((u, v))))

with open('/home/user/edges.csv', 'w') as f:
    f.write('source,target\n')
    for u, v in edges:
        f.write(f'{u},{v}\n')
EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

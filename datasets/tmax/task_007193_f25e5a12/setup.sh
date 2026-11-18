#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/model_fit.py
import random
import sys

# Simulate non-reproducible graph optimization
cost = random.uniform(1.0, 10.0)
paths = ["0-1-2-3", "0-2-1-3", "0-3-1-2", "3-2-1-0", "1-0-2-3", "0-1-3-2", "2-1-0-3"]
path = random.choice(paths)

print("Initializing molecular graph...")
print("Running gradient descent optimization...")
for i in range(3):
    print(f"Iteration {i}: intermediate cost {cost + random.uniform(0.1, 1.0):.5f}")

print(f"Final Graph Cost: {cost:.5f}")
print(f"Optimal Network Path: {path}")
EOF

    chmod +x /home/user/model_fit.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sim.py
#!/usr/bin/env python3
import argparse
import os

parser = argparse.ArgumentParser()
parser.add_argument('--mesh', type=int)
args = parser.parse_args()

threads = int(os.environ.get('OMP_NUM_THREADS', 1))

# Deterministic simulated time
t1 = 100.0
time = t1 / threads + 2.0 * (threads - 1)
print(f"{time:.4f}")
EOF

    chmod +x /home/user/sim.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

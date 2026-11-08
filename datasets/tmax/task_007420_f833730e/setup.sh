#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/simulate.py
import argparse
import numpy as np
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--k", type=float, required=True)
parser.add_argument("--d", type=float, required=True)
args = parser.parse_args()

# Simple deterministic generation mimicking an ODE final state
np.random.seed(42)
base = np.linspace(0, 1, 100).reshape(10, 10)
# Create a pattern dependent on k and d
result = base * args.k * 10 - base**2 * args.d * 100 + np.sin(base * np.pi) * (args.k / (args.d + 1e-5))
np.savetxt(sys.stdout, result, fmt='%.4f')
EOF

    chmod +x /home/user/simulate.py

    python3 /home/user/simulate.py --k 0.3 --d 0.04 > /home/user/target_data.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

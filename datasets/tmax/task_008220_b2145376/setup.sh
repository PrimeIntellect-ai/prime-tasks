#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/obs.csv
1.0,2.0,3.0
4.0,5.0,6.0
7.0,8.0,9.0
EOF

    cat << 'EOF' > /home/user/app.py
import sys
import numpy as np

def solve_pde(data):
    # Inefficient PDE step to guarantee it dominates tottime
    u = np.array(data)
    for _ in range(5000):
        temp = np.zeros_like(u)
        for i in range(len(u)):
            temp[i] = u[i] * 1.0001
        u = temp
    return u

def compute_distance(u, target):
    # Dummy distance metric (L1)
    return np.sum(np.abs(u - target))

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    with open(sys.argv[1], 'r') as f:
        data = [float(x) for x in f.read().split()]
    u = solve_pde(data)
    target = np.ones_like(u)
    dist = compute_distance(u, target)
    print(f"Distance: {dist}")

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

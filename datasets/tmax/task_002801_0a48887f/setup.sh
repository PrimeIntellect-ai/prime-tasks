#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sim_expression.py
import sys
import numpy as np

def run_sim(N):
    mesh = {}
    for i in range(N):
        for j in range(N):
            # Simulated expression level
            mesh[(i, j)] = np.sin(i*np.pi/N) * np.cos(j*np.pi/N) + 1.0

    keys = list(mesh.keys())
    np.random.seed(42)
    np.random.shuffle(keys) # Simulating unordered map / parallel gather

    # Bug: Non-deterministic float32 addition order
    total_sum = np.float32(0.0)
    for k in keys:
        total_sum += np.float32(mesh[k])

    with open(f"output_{N}.txt", "w") as f:
        f.write(f"{total_sum}\n")
        sorted_keys = sorted(mesh.keys())
        for k in sorted_keys:
            f.write(f"{mesh[k]}\n")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python sim_expression.py N")
        sys.exit(1)
    N = int(sys.argv[1])
    run_sim(N)
EOF

    chmod -R 777 /home/user

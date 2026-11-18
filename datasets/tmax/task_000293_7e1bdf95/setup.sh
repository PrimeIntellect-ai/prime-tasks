#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy matplotlib

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/workspace
    cat << 'EOF' > /home/user/workspace/benchmark.py
import numpy as np
import matplotlib.pyplot as plt
import time

# Broken: hardcoded, no seed
N = 100
A = np.random.rand(N, N)

start = time.time()
B = A @ A.T
val = np.trace(B)
end = time.time()

# Broken plot: will fail in headless
plt.plot(B[0,:])
plt.show()

print(f"Result: {val}")
EOF

    chmod -R 777 /home/user

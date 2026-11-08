#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy matplotlib scipy

mkdir -p /home/user

cat << 'EOF' > /home/user/benchmark.py
import sys
import time
import numpy as np
import matplotlib.pyplot as plt

if len(sys.argv) != 2:
    print("Usage: benchmark.py <csv_file>")
    sys.exit(1)

# Read lines just to get a size multiplier
with open(sys.argv[1], 'r') as f:
    lines = len(f.readlines())

start = time.time()
# Simulate workload
np.random.seed(42)
N = min(2000, lines * 10)
A = np.random.rand(N, N)
B = np.random.rand(N, N)
C = np.dot(A, B)
duration = time.time() - start

# Simulate plotting
plt.hist(C.flatten()[:1000])
plt.title("Output Distribution")
plt.savefig("output_plot.png")

print(f"Time: {duration:.4f}")
EOF

cat << 'EOF' > /home/user/valid.csv
id,val1,val2,label
1,0.5,0.2,0
2,0.1,0.9,1
3,0.4,0.4,0
EOF

cat << 'EOF' > /home/user/invalid.csv
id,val1,val2,target
1,0.5,0.2,0
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

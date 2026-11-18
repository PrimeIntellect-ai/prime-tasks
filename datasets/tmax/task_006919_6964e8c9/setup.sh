#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_csv.py
import numpy as np

np.random.seed(123)
N = 500
val1 = np.random.normal(10, 2, N)
# Create a val2 that is correlated with val1 (correlation roughly ~0.78)
val2 = 3.0 + 1.5 * val1 + np.random.normal(0, 2.5, N)

with open('/home/user/etl_output.csv', 'w') as f:
    f.write("val1,val2\n")
    for v1, v2 in zip(val1, val2):
        f.write(f"{v1:.4f},{v2:.4f}\n")
EOF

    python3 /home/user/generate_csv.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

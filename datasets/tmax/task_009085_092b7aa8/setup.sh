#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import os

np.random.seed(123)
n = 100
x1 = np.random.uniform(-5, 5, n)
x2 = np.random.uniform(-5, 5, n)
# True betas: beta0=2.5, beta1=1.2, beta2=-0.8
y = 2.5 + 1.2 * x1 - 0.8 * x2 + np.random.normal(0, 1, n)

with open("/home/user/data.csv", "w") as f:
    f.write("x1,x2,y\n")
    for i in range(n):
        f.write(f"{x1[i]:.4f},{x2[i]:.4f},{y[i]:.4f}\n")
EOF

    python3 /tmp/generate_data.py

    chmod -R 777 /home/user

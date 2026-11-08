#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libgsl-dev
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    # Generate the dataset
    cat << 'EOF' > /tmp/generate_data.py
import numpy as np

np.random.seed(123)
X = np.linspace(-5.0, 5.0, 50)
true_beta = [1.5, -0.8, 0.2]
Y = true_beta[0] + true_beta[1]*X + true_beta[2]*(X**2) + np.random.normal(0, 1.0, size=50)

with open("/home/user/data.csv", "w") as f:
    for x, y in zip(X, Y):
        f.write(f"{x:.6f},{y:.6f}\n")
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user

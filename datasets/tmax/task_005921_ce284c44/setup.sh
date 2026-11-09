#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import numpy as np

np.random.seed(42)
mu_true = 2.0
x = np.random.normal(mu_true, 1.0, 100)

# Solve y^3 + y - x = 0
y_obs = []
for xi in x:
    # roots of y^3 + y - xi = 0
    roots = np.roots([1, 0, 1, -xi])
    # real root
    y = roots[np.isreal(roots)][0].real
    y_obs.append(y)

with open('/home/user/y_obs.csv', 'w') as f:
    for y in y_obs:
        f.write(f"{y}\n")
EOF
    python3 /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

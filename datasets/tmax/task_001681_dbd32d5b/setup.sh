#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go wget
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import os

np.random.seed(10)
N = 100

# Feature 1
x1 = np.random.normal(0, 1, N)
# Feature 2 is highly collinear to Feature 1
x2 = x1 * 1.0 + np.random.normal(0, 1e-4, N)

X = np.column_stack((x1, x2))

# y = 2.0*x1 - 1.5*x2 + noise
y = 2.0 * x1 - 1.5 * x2 + np.random.normal(0, 0.1, N)

np.savetxt('/home/user/X.csv', X, delimiter=',')
np.savetxt('/home/user/y.csv', y, delimiter=',')

with open('/home/user/ref_w0.txt', 'w') as f:
    f.write("2.0\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import numpy as np

np.random.seed(42)

# Generate two clusters
n1, n2 = 600, 400
mean1 = [2.0, 3.0]
cov1 = [[1.0, 0.5], [0.5, 1.0]]
data1 = np.random.multivariate_normal(mean1, cov1, n1)

mean2 = [-4.0, -2.0]
cov2 = [[2.0, -1.0], [-1.0, 2.0]]
data2 = np.random.multivariate_normal(mean2, cov2, n2)

data = np.vstack((data1, data2))
np.savetxt('/home/user/points.csv', data, delimiter=',', fmt='%.6f')
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

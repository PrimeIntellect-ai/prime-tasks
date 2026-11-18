#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

data_file = '/home/user/data.csv'

np.random.seed(42)
X = np.random.normal(10, np.sqrt(3), 100)
Y = 0.5 * X + np.random.normal(0, 1, 100)

with open(data_file, 'w') as f:
    for x, y in zip(X, Y):
        f.write(f"{x:.6f},{y:.6f}\n")

cov = np.cov(X, Y, ddof=1)[0, 1]
mean_x = np.mean(X)
n = len(X)
prior_mean = 5.0
prior_var = 2.0
data_var = 3.0

post_mean = (prior_mean / prior_var + n * mean_x / data_var) / (1 / prior_var + n / data_var)

expected_output = f"Covariance: {cov:.4f}\nPosterior Mean: {post_mean:.4f}\n"

with open('/home/user/expected_results.txt', 'w') as f:
    f.write(expected_output)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest numpy

mkdir -p /home/user

cat << 'EOF' > /home/user/setup_data.py
import numpy as np
np.random.seed(123)
theta1, theta2 = 2.5, -1.2
data = np.zeros((10, 10))
for i in range(10):
    for j in range(10):
        y_true = theta1 * (i**2) + theta2 * (j**2)
        data[i, j] = y_true + np.random.normal(0, 5.0)

with open('/home/user/data.txt', 'w') as f:
    for i in range(10):
        f.write(' '.join(f"{val:.4f}" for val in data[i, :]) + '\n')
EOF
python3 /home/user/setup_data.py
rm /home/user/setup_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

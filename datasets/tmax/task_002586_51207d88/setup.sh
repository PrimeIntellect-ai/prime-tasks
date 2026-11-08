#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

# Setup sequence.txt
seq_content = "CCATCGTACGTAGGTCTCATGCCGTAGCTAGCTGAC"
with open("/home/user/sequence.txt", "w") as f:
    f.write(seq_content)

# Setup qpcr_data.csv
np.random.seed(42)
x_all = np.arange(1, 41)
data = []
for i in range(96):
    A = np.random.uniform(10, 20)
    r = np.random.uniform(0.1, 0.3)
    noise = np.random.normal(0, 0.5, 40)
    y = A * np.exp(r * x_all) + noise
    data.append(y)

np.savetxt('/home/user/qpcr_data.csv', data, delimiter=',')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

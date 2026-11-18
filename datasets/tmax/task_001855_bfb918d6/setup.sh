#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_data.py
import numpy as np

# Generate 10,000,000 double precision floats
np.random.seed(42)
data = np.random.normal(loc=25.0, scale=4.0, size=10000000)

# Inject specific anomalies outside the 3-sigma range (25 +/- 12) -> < 13 or > 37
anomalies = [10.5, 5.0, 45.2, 88.8, -12.4, 39.1]
indices = [100, 5000, 99999, 150000, 5000000, 9999999]

for idx, val in zip(indices, anomalies):
    data[idx] = val

data.astype(np.float64).tofile('/home/user/raw_data.bin')
EOF

    python3 generate_data.py
    rm generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

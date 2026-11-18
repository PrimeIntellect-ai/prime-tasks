#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest numpy

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /tmp/generate_data.py
import csv
import numpy as np

np.random.seed(42)

# Generate Query
query_vector = np.random.rand(10).astype(np.float64)
with open('/home/user/data/query.csv', 'w') as f:
    writer = csv.writer(f)
    writer.writerow(["query"] + query_vector.tolist())

# Generate Database
with open('/home/user/data/database.csv', 'w') as f:
    writer = csv.writer(f)
    for i in range(1000):
        vec = np.random.rand(10).astype(np.float64)
        writer.writerow([i] + vec.tolist())
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

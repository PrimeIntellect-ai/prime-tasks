#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import numpy as np

np.random.seed(42)
# Generate 10000 vectors of 10 dimensions
data = np.random.uniform(-10, 10, size=(10000, 10))

# Save to CSV
np.savetxt('/home/user/raw_vectors.csv', data, delimiter=',', fmt='%.4f')
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user

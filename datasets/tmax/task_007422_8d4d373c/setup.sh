#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate data
    cat << 'EOF' > /tmp/setup_data.py
import os
import numpy as np

os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(42)

# Dimensions
N = 500  # items
M = 20   # queries
D = 32   # embedding size

# Generate Experiment A (unnormalized)
items_A = np.random.randn(N, D)
np.save('/home/user/data/experiment_A_items.npy', items_A)

# Generate Experiment B (already normalized)
items_B = np.random.randn(N, D)
items_B = items_B / np.linalg.norm(items_B, axis=1, keepdims=True)
np.save('/home/user/data/experiment_B_items.npy', items_B)

# Generate queries (unnormalized, with NaNs)
queries = np.random.randn(M, D)
queries[4, 10] = np.nan
queries[12, 5] = np.nan
queries[17, 31] = np.nan
np.save('/home/user/data/queries.npy', queries)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    # Set permissions
    chmod -R 777 /home/user

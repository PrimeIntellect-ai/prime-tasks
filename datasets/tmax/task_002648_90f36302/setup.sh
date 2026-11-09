#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    mkdir -p /home/user/src /home/user/tests /home/user/output

    cat << 'EOF' > /home/user/src/run_etl.py
import os
import json
import numpy as np

seed = os.environ.get("ETL_SEED")
if seed is not None:
    np.random.seed(int(seed))

# Generate dummy similarity matrix
n_items = 10
features = np.random.randn(n_items, 5)
norms = np.linalg.norm(features, axis=1, keepdims=True)
features_normalized = features / norms
similarity = np.dot(features_normalized, features_normalized.T)

# Generate dummy posteriors
posteriors = {}
for i in range(n_items):
    alpha = np.random.uniform(1, 50)
    beta = np.random.uniform(1, 50)
    posteriors[str(i)] = {"alpha": alpha, "beta": beta}

np.save('/home/user/output/similarity.npy', similarity)
with open('/home/user/output/posteriors.json', 'w') as f:
    json.dump(posteriors, f, indent=2)
EOF

    chmod +x /home/user/src/run_etl.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

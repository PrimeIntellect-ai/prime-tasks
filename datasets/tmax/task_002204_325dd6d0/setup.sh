#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import json
import os

os.makedirs('/home/user', exist_ok=True)

np.random.seed(42)
embeddings = np.random.rand(100, 10)
projection = np.random.rand(10, 3)

np.savetxt('/home/user/embeddings.csv', embeddings, delimiter=',', fmt='%.6f')
np.savetxt('/home/user/projection.csv', projection, delimiter=',', fmt='%.6f')

reduced = np.dot(embeddings, projection)

recs = {}
for i in range(100):
    dists = np.linalg.norm(reduced - reduced[i], axis=1)
    closest = np.argsort(dists)
    closest = [int(x) for x in closest if x != i]
    recs[str(i)] = closest[:2]

with open('/home/user/expected_recs.json', 'w') as f:
    json.dump(recs, f)
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

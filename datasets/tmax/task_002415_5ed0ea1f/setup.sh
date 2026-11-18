#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np

np.random.seed(42)
X = np.random.randn(100, 3)
true_w = np.array([1.5, -2.0, 0.5])
y = X.dot(true_w) + np.random.randn(100) * 0.1

np.savetxt('/home/user/embeddings.csv', X, delimiter=',')
np.savetxt('/home/user/targets.csv', y, delimiter=',')

# Artifact weights (perturbed intentionally to fail reproducibility)
art_w = true_w + np.array([0.1, -0.05, 0.2])
np.savetxt('/home/user/model_artifact.txt', art_w.reshape(1, -1), delimiter=',')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

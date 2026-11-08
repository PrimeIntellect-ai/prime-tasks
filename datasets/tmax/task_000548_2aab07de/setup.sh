#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import pandas as pd
import numpy as np

# Set seed for deterministic raw data generation
np.random.seed(100)

data = []
labels = ['A', 'B', 'C', 'UNKNOWN']
scores = [0.1, 0.5, 0.9, 1.2, -0.5, 'ERROR', '', 0.0, 1.0]

for i in range(1, 201):
    feat = round(np.random.randn(), 4)
    label = labels[i % len(labels)]
    score = scores[i % len(scores)]
    data.append([i, feat, score, label])

df = pd.DataFrame(data, columns=['id', 'feature_1', 'prediction_score', 'label'])
df.to_csv('/home/user/inference_data.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user

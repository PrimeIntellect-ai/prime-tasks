#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np

np.random.seed(42)
data = np.random.randn(100, 5) * 2.0 + 1.0

# Inject NaNs
nan_indices = [(5, 2), (15, 4), (25, 1), (35, 0), (50, 3), (75, 2), (90, 4)]
for r, c in nan_indices:
    data[r, c] = np.nan

# Inject Outliers
outlier_indices = [(10, 1), (40, 2), (60, 3), (80, 0)]
data[10, 1] = 20.0
data[40, 2] = -20.0
data[60, 3] = 25.0
data[80, 0] = -25.0

with open("/home/user/embeddings.csv", "w") as f:
    for row in data:
        row_strs = ["NaN" if np.isnan(x) else f"{x:.6f}" for x in row]
        f.write(",".join(row_strs) + "\n")
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user

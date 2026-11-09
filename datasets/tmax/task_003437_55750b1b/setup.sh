#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import numpy as np

# Set reproducible seed
np.random.seed(42)

# Generate 10000 rows, 50 columns of double precision floats
data = np.random.randn(10000, 50).astype(np.float64)

# Save to binary file
data.tofile('/home/user/dataset.bin')

# Compute truth for verification
traces = []
for k in range(5):
    fold_data = data[k*2000:(k+1)*2000, :]
    # Compute sum of sample variances (ddof=1)
    trace = np.sum(np.var(fold_data, axis=0, ddof=1))
    traces.append(trace)

with open('/home/user/expected_variances.csv', 'w') as f:
    f.write("Fold,Trace\n")
    for k, t in enumerate(traces):
        f.write(f"{k},{t:.4f}\n")
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

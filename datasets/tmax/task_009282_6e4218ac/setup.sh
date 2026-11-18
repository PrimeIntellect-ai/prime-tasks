#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np

np.random.seed(42)
n_samples = 500

cpu = np.random.uniform(10, 100, n_samples)
mem = np.random.uniform(20, 100, n_samples)
io = np.random.exponential(50, n_samples)

# Create a complex relationship for the target
logits = -5 + 0.05 * cpu + 0.02 * mem + 0.001 * (cpu * io)
probs = 1 / (1 + np.exp(-logits))
failure = np.random.binomial(1, probs)

df = pd.DataFrame({'cpu': cpu, 'mem': mem, 'io': io, 'failure': failure})
df.to_csv('/home/user/telemetry.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

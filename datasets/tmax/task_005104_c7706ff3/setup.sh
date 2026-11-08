#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl tar
    pip3 install pytest pandas numpy scikit-learn

    mkdir -p /home/user/data
    mkdir -p /app

    # Generate dataset
    cat << 'EOF' > /tmp/generate_data.py
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user/data', exist_ok=True)

# Generate dataset
np.random.seed(42)
n = 500
cpu = np.random.uniform(10, 90, n)
mem = np.random.uniform(20, 100, n)
disk = np.random.exponential(200, n)
net = np.random.normal(50, 15, n)

# Introduce latency with correlations: high to cpu, moderate to mem
latency = 5.0 + 2.5 * cpu + 1.2 * mem + np.random.normal(0, 5, n)

# Inject missing values and outliers
cpu[np.random.choice(n, 20, replace=False)] = np.nan
disk[np.random.choice(n, 10, replace=False)] = 1500 # Outliers > 1000

df = pd.DataFrame({
    'cpu_usage': cpu,
    'mem_usage': mem,
    'disk_io': disk,
    'network_in': net,
    'latency': latency
})
df.to_csv('/home/user/data/server_metrics.csv', index=False)
EOF
    python3 /tmp/generate_data.py

    # Setup vendored package
    curl -sL https://github.com/bottlepy/bottle/archive/refs/tags/0.12.25.tar.gz | tar -xz -C /app

    # Inject perturbation
    cat << 'EOF' > /tmp/patch_bottle.py
bottle_file = "/app/bottle-0.12.25/bottle.py"
with open(bottle_file, "r") as f:
    code = f.read()

# Inject deliberate perturbation
broken_code = code.replace("def route(self,", "def route(self,\n        raise RuntimeError('Broken by scanner')")
with open(bottle_file, "w") as f:
    f.write(broken_code)
EOF
    python3 /tmp/patch_bottle.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

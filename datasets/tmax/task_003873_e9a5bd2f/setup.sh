#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest pandas numpy scikit-learn flask requests

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n_samples = 1000

# Base features
cpu_load = np.random.normal(50, 15, n_samples)
disk_io = np.random.normal(100, 30, n_samples)
net_rx = np.random.normal(500, 100, n_samples)
memory_usage = np.random.normal(60, 20, n_samples)

# Highly correlated features (>0.85)
# cpu_load -> temp_celsius (temp_celsius dropped as t > c)
temp_celsius = 30 + 0.6 * cpu_load + np.random.normal(0, 2, n_samples) 

# net_rx -> net_tx (net_tx dropped as net_t > net_r)
net_tx = 1.1 * net_rx + np.random.normal(0, 10, n_samples)

# Target variable (probabilistic generation)
# Anomaly if cpu_load is high or net_rx is high
logits = -5 + 0.05 * cpu_load + 0.005 * net_rx + np.random.normal(0, 1, n_samples)
probs = 1 / (1 + np.exp(-logits))
is_anomaly = (probs > 0.5).astype(int)

df = pd.DataFrame({
    'cpu_load': cpu_load,
    'disk_io': disk_io,
    'net_rx': net_rx,
    'memory_usage': memory_usage,
    'temp_celsius': temp_celsius,
    'net_tx': net_tx,
    'is_anomaly': is_anomaly
})

# Inject missing values
# Drop some target values
missing_target_idx = np.random.choice(n_samples, 20, replace=False)
df.loc[missing_target_idx, 'is_anomaly'] = np.nan

# Inject missing values in features
for col in ['cpu_load', 'disk_io', 'net_rx', 'memory_usage']:
    missing_idx = np.random.choice(n_samples, 50, replace=False)
    df.loc[missing_idx, col] = np.nan

df.to_csv('/home/user/system_metrics.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user

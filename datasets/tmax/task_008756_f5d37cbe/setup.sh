#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n = 500
s1 = np.random.randn(n)
# sensor_2 is highly correlated with sensor_1
s2 = s1 * 0.9 + np.random.randn(n) * 0.1  
s3 = np.random.randn(n)

ec = np.random.poisson(5, n).astype(float)
missing_idx = np.random.choice(n, 50, replace=False)
ec[missing_idx] = np.nan

# True generating function
load = 2.5 * s1 + 1.2 * s3 + 0.5 * ec + np.random.randn(n) * 0.5
load[missing_idx] = 2.5 * s1[missing_idx] + 1.2 * s3[missing_idx] + 0.5 * 5.0 + np.random.randn(50) * 0.5

df = pd.DataFrame({
    'sensor_1': s1, 
    'sensor_2': s2, 
    'sensor_3': s3, 
    'event_count': ec, 
    'system_load': load
})

df['event_count'] = df['event_count'].apply(lambda x: '' if np.isnan(x) else str(int(x)))
df.to_csv('/home/user/data/sensor_log.csv', index=False)
EOF
    python3 /home/user/data/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

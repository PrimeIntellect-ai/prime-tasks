#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy matplotlib

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)

def generate_server_data(server_id, mean, std, count=100):
    return pd.DataFrame({
        'server_id': [server_id] * count,
        'timestamp': pd.date_range(start='2023-01-01', periods=count, freq='h'),
        'response_time': np.random.normal(mean, std, count)
    })

df = pd.concat([
    generate_server_data('srv_target', 105.0, 10.0),
    generate_server_data('srv_alpha', 150.0, 15.0),
    generate_server_data('srv_beta', 106.5, 10.0), # Closest to target
    generate_server_data('srv_gamma', 200.0, 20.0),
    generate_server_data('srv_delta', 90.0, 8.0),
])

df.to_csv('/home/user/data/metrics.csv', index=False)
EOF
    python3 /home/user/data/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

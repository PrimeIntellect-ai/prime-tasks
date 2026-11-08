#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy networkx

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)

# Generate telemetry.csv
telemetry_data = {
    'timestamp': [1000, 1001, 1002, 1003, 1004, 1000, 1001, 1002, 1003, 1004],
    'server_id': ['S1', 'S1', 'S1', 'S1', 'S1', 'S2', 'S2', 'S2', 'S2', 'S2'],
    'cpu_usage': [40.0, np.nan, 50.0, np.nan, 60.0, 20.0, 25.0, np.nan, 35.0, 40.0],
    'memory_usage': [1024.0, 1048.0, np.nan, 1096.0, 1120.0, 512.0, np.nan, 600.0, 644.0, 688.0]
}
df_tel = pd.DataFrame(telemetry_data)
df_tel.to_csv('/home/user/telemetry.csv', index=False)

# Generate access.csv
access_data = {
    'timestamp': [1000, 1001, 1002, 1003, 1004, 1000, 1001, 1002],
    'server_id': ['S1', 'S1', 'S1', 'S2', 'S2', 'S2', 'S2', 'S1'], # Intentionally mixed
    'user_email': ['alice@test.com', 'bob@test.com', 'alice@test.com', 'charlie@test.com', 'bob@test.com', 'charlie@test.com', 'alice@test.com', 'diana@test.com'],
    'user_ip': ['10.0.0.15', '192.168.1.100', '10.0.0.22', '172.16.0.5', '192.168.1.105', '172.16.0.8', '10.0.0.50', '10.1.1.1']
}
df_acc = pd.DataFrame(access_data)
df_acc.to_csv('/home/user/access.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

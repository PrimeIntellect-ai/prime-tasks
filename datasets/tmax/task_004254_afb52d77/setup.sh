#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow fastparquet

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /tmp/setup.py
import os
import pandas as pd
import json

os.makedirs('/home/user/data', exist_ok=True)
os.makedirs('/home/user/output', exist_ok=True)

# 1. Generate CSV with embedded newlines
csv_data = [
    {"timestamp": "2023-10-01T10:00:00Z", "server_name": "SRV-01", "raw_diff": "System rebooted\n[UPDATE] max_connections=100\n[ADD] timeout=30\nDone."},
    {"timestamp": "2023-10-01T11:30:00Z", "server_name": "srv_02", "raw_diff": "[UPDATE] cache_size=1024"},
    {"timestamp": "2023-10-01T12:00:00Z", "server_name": "SRV-01", "raw_diff": "Warning: load high\n[UPDATE] workers=8\nResolving..."},
    {"timestamp": "2023-10-01T14:30:00Z", "server_name": "SRV_01", "raw_diff": "Routine\n[ADD] backup_path=/tmp\n"},
]
df_csv = pd.DataFrame(csv_data)
df_csv.to_csv('/home/user/data/legacy_configs.csv', index=False)

# 2. Generate JSON
json_data = [
    {"time": "2023-10-01T10:15:00Z", "host_id": "srv-02", "changed_keys": ["ssl_cert"]},
    {"time": "2023-10-01T13:45:00Z", "host_id": "SRV-01", "changed_keys": ["db_host", "db_port"]},
]
with open('/home/user/data/modern_configs.json', 'w') as f:
    json.dump(json_data, f)
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

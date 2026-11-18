#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make coreutils grep sed
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > /tmp/generate_logs.py
import os
import random
from datetime import datetime, timedelta

os.makedirs('/home/user/logs', exist_ok=True)

random.seed(42)
services = ['auth-service', 'web-frontend', 'payment-gateway', 'db-worker']
keys = ['timeout', 'max_connections', 'retry_limit', 'cache_size']

start_time = datetime(2023, 10, 1)

for file_idx in range(1, 5):
    with open(f'/home/user/logs/update_{file_idx:02d}.log', 'w') as f:
        current_time = start_time + timedelta(days=file_idx)
        for i in range(5000):
            # Advance time randomly
            current_time += timedelta(seconds=random.randint(1, 60))

            if random.random() < 0.1: # 10% chance of config update
                service = random.choice(services)
                key = random.choice(keys)
                old_val = str(random.randint(10, 100))
                new_val = str(random.randint(10, 100))
                f.write(f"[{current_time.strftime('%Y-%m-%dT%H:%M:%S')}] [{service}] CONFIG_UPDATE: {key} changed from '{old_val}' to '{new_val}'\n")
            else:
                f.write(f"[{current_time.strftime('%Y-%m-%dT%H:%M:%S')}] [{random.choice(services)}] INFO: Standard log line {random.randint(1000, 9999)}\n")
EOF

    python3 /tmp/generate_logs.py

    cat /home/user/logs/*.log | grep "CONFIG_UPDATE" | sed -E "s/\[(.*)\] \[(.*)\] CONFIG_UPDATE: (.*) changed from '(.*)' to '(.*)'/\1,\2,\3,\4,\5/" | sort > /home/user/expected_import.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

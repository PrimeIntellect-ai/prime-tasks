#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scipy matplotlib pandas

    mkdir -p /home/user/logs
    cat << 'EOF' > /home/user/setup_logs.py
import json
import os

os.makedirs('/home/user/logs', exist_ok=True)
for i in range(1, 51):
    t = float(i)
    l = 0.5 * t + (i % 4)
    data = {
        "experiment_id": f"exp_{i}",
        "metrics": {
            "training_time": t,
            "val_loss": l
        }
    }
    with open(f'/home/user/logs/run_{i:03d}.json', 'w') as f:
        json.dump(data, f)
EOF
    python3 /home/user/setup_logs.py
    rm /home/user/setup_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

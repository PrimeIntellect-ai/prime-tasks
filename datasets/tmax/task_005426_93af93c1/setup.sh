#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/setup.py
import os
import json
import random

os.makedirs('/home/user/data', exist_ok=True)
random.seed(123)

with open('/home/user/data/server_metrics.jsonl', 'w') as f:
    for i in range(1000):
        # Generate some synthetic data where error is somewhat predictable
        cpu = random.uniform(0.1, 99.9)
        mem = random.uniform(1.0, 64.0)
        disk = random.uniform(10, 500)

        # High CPU and High Mem increases chance of error
        error_prob = (cpu / 100.0) * 0.5 + (mem / 64.0) * 0.4
        is_error = 1 if random.random() < error_prob else 0

        record = {
            "timestamp": f"2023-10-01T12:{i//60:02d}:{i%60:02d}Z",
            "metrics": {
                "cpu_utilization": cpu,
                "memory_gb": mem,
                "disk_io": disk,
                "network_drop": random.randint(0, 10)
            },
            "status": {
                "error_code": random.choice([404, 500, 503]) if is_error else 0,
                "message": "Error" if is_error else "OK"
            }
        }
        f.write(json.dumps(record) + '\n')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

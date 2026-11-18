#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy

    mkdir -p /home/user

    python3 -c "
import json
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)
np.random.seed(123)
# Generate 500 sales records
data = np.random.normal(100, 20, 500)

with open('/home/user/raw_etl_data.jsonl', 'w') as f:
    for i, val in enumerate(data):
        f.write(json.dumps({'id': i, 'sales_amount': float(val)}) + '\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

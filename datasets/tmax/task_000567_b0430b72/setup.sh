#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server nginx cargo rustc curl build-essential
    pip3 install pytest flask redis

    mkdir -p /app/tracking_system
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /app/tracking_system/app.py
from flask import Flask, request
import redis
import json

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/api/artifacts', methods=['POST'])
def artifacts():
    data = request.json
    # TODO: integrate Rust CLI anomaly detector here
    r.set("last_artifact", json.dumps(data))
    return "OK", 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/tracking_system/nginx.conf
# TODO: configure reverse proxy
EOF

    python3 -c "
import json
import random
import math
import os

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

for i in range(50):
    data = {
        'gradient_norms': [random.uniform(0, 10) for _ in range(100)],
        'loss_values': [random.uniform(0, 1) for _ in range(100)],
        'missing_ratio': random.uniform(0, 0.04)
    }
    with open(f'/app/corpus/clean/clean_{i}.json', 'w') as f:
        json.dump(data, f)

for i in range(15):
    data = {
        'gradient_norms': [random.uniform(0, 10) for _ in range(100)],
        'loss_values': [random.uniform(0, 1) for _ in range(100)],
        'missing_ratio': 0.01
    }
    data['loss_values'][10] = float('nan')
    with open(f'/app/corpus/evil/evil_nan_{i}.json', 'w') as f:
        json.dump(data, f)

for i in range(15):
    data = {
        'gradient_norms': [random.uniform(0, 10) for _ in range(100)],
        'loss_values': [random.uniform(0, 1) for _ in range(100)],
        'missing_ratio': random.uniform(0.06, 0.5)
    }
    with open(f'/app/corpus/evil/evil_missing_{i}.json', 'w') as f:
        json.dump(data, f)

for i in range(10):
    data = {
        'gradient_norms': [2000.0 for _ in range(100)],
        'loss_values': [random.uniform(0, 1) for _ in range(100)],
        'missing_ratio': 0.01
    }
    with open(f'/app/corpus/evil/evil_grad_{i}.json', 'w') as f:
        json.dump(data, f)

for i in range(10):
    data = {
        'gradient_norms': [random.uniform(0, 10) for _ in range(100)],
        'loss_values': [0.0 if j % 2 == 0 else 1000.0 for j in range(100)],
        'missing_ratio': 0.01
    }
    with open(f'/app/corpus/evil/evil_var_{i}.json', 'w') as f:
        json.dump(data, f)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl
    pip3 install pytest flask redis numpy scipy

    mkdir -p /app
    cat << 'EOF' > /app/data_api.py
import os
import json
import numpy as np
from flask import Flask, jsonify
import redis

app = Flask(__name__)
r = redis.from_url(os.environ.get("REDIS_URL", "redis://localhost:6379/0"))

TRUE_MU = 4.2

@app.route('/generate', methods=['GET'])
def generate():
    np.random.seed(42)
    n_samples = 1500
    # 70% Gaussian, 30% Uniform
    mask = np.random.rand(n_samples) < 0.7
    gaussian = np.random.normal(TRUE_MU, 2.0, n_samples)
    uniform = np.random.uniform(-15, 15, n_samples)
    data = np.where(mask, gaussian, uniform)
    r.set("dataset", json.dumps(data.tolist()))
    return jsonify({"status": "generated"})

@app.route('/data', methods=['GET'])
def get_data():
    data = r.get("dataset")
    if not data:
        return jsonify({"error": "No data"}), 400
    return data, 200, {'Content-Type': 'application/json'}

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go redis-server
    pip3 install pytest flask redis pyyaml

    mkdir -p /app/corpora/clean /app/corpora/evil /app/services

    # Generate synthetic data
    python3 -c "
import json
import random
import os

os.makedirs('/app/corpora/clean', exist_ok=True)
os.makedirs('/app/corpora/evil', exist_ok=True)

# Clean data
for i in range(10):
    x = [j * 0.01 for j in range(1000)]
    y = [random.gauss(0, 0.005) for _ in range(1000)]
    y[500] = 0.2  # significant peak
    with open(f'/app/corpora/clean/clean_{i}.json', 'w') as f:
        json.dump({'x': x, 'y': y}, f)

# Evil data - high drift
for i in range(5):
    x = [j * 0.01 for j in range(1000)]
    y = [0.06 * xi + random.gauss(0, 0.005) for xi in x]
    y[500] += 0.2
    with open(f'/app/corpora/evil/evil_drift_{i}.json', 'w') as f:
        json.dump({'x': x, 'y': y}, f)

# Evil data - no significant peak
for i in range(5):
    x = [j * 0.01 for j in range(1000)]
    y = [random.gauss(0, 0.005) for _ in range(1000)]
    with open(f'/app/corpora/evil/evil_noise_{i}.json', 'w') as f:
        json.dump({'x': x, 'y': y}, f)
"

    # Create ingestion service
    cat << 'EOF' > /app/services/ingest.py
import os
import tempfile
import subprocess
import yaml
import json
import redis
from flask import Flask, request, jsonify

app = Flask(__name__)

with open('/app/services/config.yaml', 'r') as f:
    config = yaml.safe_load(f)

r = redis.Redis(host=config.get('redis_host', 'localhost'), port=config.get('redis_port', 6379), db=0)

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.json
    if not data:
        return jsonify({"error": "no data"}), 400

    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.json') as tmp:
        json.dump(data, tmp)
        tmp_path = tmp.name

    try:
        res = subprocess.run([config['filter_bin'], tmp_path], capture_output=True)
        if res.returncode == 0:
            r.rpush('valid_spectra', json.dumps(data))
            return jsonify({"status": "accepted"}), 200
        else:
            return jsonify({"status": "rejected"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)
EOF

    # Create dummy config
    cat << 'EOF' > /app/services/config.yaml
redis_host: "invalid.host"
redis_port: 0
filter_bin: "/path/to/nowhere"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

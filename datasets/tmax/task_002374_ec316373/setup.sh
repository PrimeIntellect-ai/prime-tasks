#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install --no-cache-dir pytest numpy pandas scikit-learn flask redis

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline
    mkdir -p /home/user/train_data/clean /home/user/train_data/evil
    mkdir -p /home/user/test_data/clean /home/user/test_data/evil
    mkdir -p /home/user/accepted /home/user/rejected

    cat << 'EOF' > /home/user/pipeline/api.py
from flask import Flask, request, jsonify
import redis
import os
import json

app = Flask(__name__)
r = redis.Redis.from_url(os.environ.get('REDIS_URL', 'redis://localhost:6379/0'))

@app.route('/process', methods=['POST'])
def process():
    data = request.json
    file_path = data.get('file_path')
    if file_path:
        r.lpush('job_queue', json.dumps({'file_path': file_path}))
        return jsonify({"status": "queued"}), 200
    return jsonify({"error": "no file_path"}), 400

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /home/user/pipeline/worker.py
import redis
import os
import json
import subprocess
import time
import shutil

r = redis.Redis.from_url(os.environ.get('REDIS_URL', 'redis://localhost:6379/1')) # Missing or wrong in start script

def work():
    while True:
        item = r.brpop('job_queue', timeout=1)
        if item:
            _, data = item
            job = json.loads(data)
            file_path = job['file_path']
            filename = os.path.basename(file_path)
            result = subprocess.run(['python3', '/home/user/detector.py', file_path])
            if result.returncode == 0:
                shutil.copy(file_path, os.path.join('/home/user/accepted', filename))
            else:
                shutil.copy(file_path, os.path.join('/home/user/rejected', filename))
        else:
            time.sleep(0.1)

if __name__ == '__main__':
    work()
EOF

    cat << 'EOF' > /home/user/pipeline/start_worker.sh
#!/bin/bash
# REDIS_URL needs to be configured here
python3 /home/user/pipeline/worker.py
EOF
    chmod +x /home/user/pipeline/start_worker.sh

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd

def generate_clean(n_samples=100, n_features=5):
    A = np.random.randn(n_features, n_features)
    cov = np.dot(A, A.transpose())
    data = np.random.multivariate_normal(np.zeros(n_features), cov, n_samples)
    return pd.DataFrame(data)

def generate_evil(n_samples=100, n_features=5):
    data = generate_clean(n_samples, n_features - 1)
    weights = np.random.randn(n_features - 1)
    collinear = np.dot(data.values, weights) + np.random.randn(n_samples) * 1e-4
    data[n_features - 1] = collinear
    return data

for split, n_files in [('train', 10), ('test', 10)]:
    for i in range(n_files):
        generate_clean().to_csv(f'/home/user/{split}_data/clean/data_{i}.csv', index=False)
        generate_evil().to_csv(f'/home/user/{split}_data/evil/data_{i}.csv', index=False)
EOF
    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user

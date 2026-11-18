#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server nginx
pip3 install pytest flask redis numpy requests

mkdir -p /app/services
mkdir -p /app/corpora/clean
mkdir -p /app/corpora/evil

cat << 'EOF' > /app/services/api.py
from flask import Flask, request
import redis
app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)
@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.json
    if not data: return "Bad", 400
    r.incr("ingest_count")
    return "OK", 200
if __name__ == '__main__':
    app.run(port=5000)
EOF

cat << 'EOF' > /app/services/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

cat << 'EOF' > /tmp/generate_data.py
import os
import json
import numpy as np

np.random.seed(42)
for i in range(50):
    X = np.random.randn(10, 5)
    y = np.random.randn(10)
    with open(f'/app/corpora/clean/data_{i}.json', 'w') as f:
        json.dump({"X": X.tolist(), "y": y.tolist()}, f)

for i in range(25):
    X = np.random.randn(10, 5)
    X[:, 2] = X[:, 1] * 2.0 # Multicollinear
    y = np.random.randn(10)
    with open(f'/app/corpora/evil/collinear_{i}.json', 'w') as f:
        json.dump({"X": X.tolist(), "y": y.tolist()}, f)

for i in range(25):
    X = np.random.randn(10, 5)
    y = X[:, 3] * 1.5 # Target leak
    with open(f'/app/corpora/evil/leak_{i}.json', 'w') as f:
        json.dump({"X": X.tolist(), "y": y.tolist()}, f)
EOF

python3 /tmp/generate_data.py
rm /tmp/generate_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

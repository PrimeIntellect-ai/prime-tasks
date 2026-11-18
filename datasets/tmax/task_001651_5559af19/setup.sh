#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server gcc curl
    pip3 install pytest flask redis

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/generate_data.py
import os
import random

random.seed(42)

for i in range(50):
    with open(f'/app/corpus/clean/sample{i}.csv', 'w') as f:
        f.write("X,Y\n")
        for j in range(100):
            x = random.uniform(0, 10)
            y = 2.0 * x + 1.0 + random.gauss(0, 0.5)
            f.write(f"{x},{y}\n")

for i in range(50):
    with open(f'/app/corpus/evil/sample{i}.csv', 'w') as f:
        f.write("X,Y\n")
        for j in range(100):
            x = random.uniform(0, 10)
            y = 2.0 * x + 1.0 + random.gauss(0, 5.0)
            f.write(f"{x},{y}\n")
EOF

    python3 /app/generate_data.py
    rm /app/generate_data.py

    cat << 'EOF' > /app/api.py
from flask import Flask, request, jsonify
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/api/enqueue', methods=['POST'])
def enqueue():
    data = request.json
    if not data or 'filepath' not in data:
        return jsonify({"error": "filepath required"}), 400
    r.lpush('sensor_jobs', data['filepath'])
    return jsonify({"status": "queued"}), 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

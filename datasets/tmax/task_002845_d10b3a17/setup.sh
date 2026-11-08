#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl
    pip3 install --default-timeout=100 pytest numpy flask redis

    mkdir -p /home/user/sim_data/clean /home/user/sim_data/evil /home/user/services/data

    cat << 'EOF' > /home/user/generate_data.py
import numpy as np
import os

np.random.seed(42)
for i in range(50):
    np.save(f"/home/user/sim_data/clean/clean_{i}.npy", np.random.normal(0, 1, (1000, 64)))

for i in range(25):
    data = np.random.normal(0, 1, (1000, 64))
    data[500, 32] = np.nan
    np.save(f"/home/user/sim_data/evil/evil_nan_{i}.npy", data)

for i in range(25):
    data = np.random.normal(0, 1, (1000, 64))
    t = np.arange(1000)
    data += 0.5 * np.sin(2 * np.pi * 0.123 * t)[:, None]
    np.save(f"/home/user/sim_data/evil/evil_rfi_{i}.npy", data)
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    cat << 'EOF' > /home/user/services/producer.py
import redis
import os
import time
import threading
import shutil
from http.server import HTTPServer, SimpleHTTPRequestHandler

def run_server():
    os.chdir('/home/user/services')
    server = HTTPServer(('0.0.0.0', 8080), SimpleHTTPRequestHandler)
    server.serve_forever()

if __name__ == '__main__':
    threading.Thread(target=run_server, daemon=True).start()
    r = redis.Redis(host='localhost', port=6379, db=0)
    time.sleep(1)

    os.makedirs('/home/user/services/data', exist_ok=True)

    for i in range(10):
        shutil.copy(f"/home/user/sim_data/clean/clean_{i}.npy", f"/home/user/services/data/clean_{i}.npy")
        r.rpush('raw_data_queue', f"clean_{i}")

    for i in range(10):
        shutil.copy(f"/home/user/sim_data/evil/evil_nan_{i}.npy", f"/home/user/services/data/evil_nan_{i}.npy")
        r.rpush('raw_data_queue', f"evil_nan_{i}")

    while True:
        time.sleep(10)
EOF

    cat << 'EOF' > /home/user/services/aggregator.py
from flask import Flask, request
import json

app = Flask(__name__)

@app.route('/register', methods=['POST'])
def register():
    data = request.json
    with open('/home/user/registered.log', 'a') as f:
        f.write(json.dumps(data) + "\n")
    return "OK", 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=9090)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

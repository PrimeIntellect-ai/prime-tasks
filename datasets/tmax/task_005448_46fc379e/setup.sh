#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git sqlite3 libgl1 libglib2.0-0
    pip3 install pytest flask opencv-python-headless numpy

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/incident_data
    mkdir -p /home/user/service_repo

    # Generate incident video and sqlite db
    cat << 'EOF' > /tmp/setup.py
import cv2
import numpy as np
import sqlite3
import os

# Video Generation
out = cv2.VideoWriter('/app/incident.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (64, 64))
for i in range(120):
    frame = np.zeros((64, 64, 3), dtype=np.uint8)
    if i == 87:
        frame[:] = (0, 0, 255) # BGR for OpenCV
    out.write(frame)
out.release()

# Database Generation
db_path = '/home/user/incident_data/metrics.db'
conn = sqlite3.connect(db_path, isolation_level=None)
conn.execute('PRAGMA journal_mode=WAL;')
conn.execute('CREATE TABLE jobs (processed_id INTEGER);')
for i in range(1, 14001):
    conn.execute(f'INSERT INTO jobs (processed_id) VALUES ({i});')
conn.close()

# Uncommitted data in WAL
conn = sqlite3.connect(db_path)
conn.execute('PRAGMA synchronous=OFF;')
for i in range(14001, 14093):
    conn.execute(f'INSERT INTO jobs (processed_id) VALUES ({i});')
conn.commit()
# Exit without closing to leave WAL intact
os._exit(0)
EOF
    python3 /tmp/setup.py

    # Setup Git Forensics
    cd /home/user/service_repo
    git init
    git config --global user.email "dev@example.com"
    git config --global user.name "Dev"
    echo "Initial config" > config.py
    git add config.py
    git commit -m "Initial commit"
    echo 'SECRET_TOKEN="dev_token_9x2b_lost"' >> config.py
    git add config.py
    git commit -m "Add secret config"
    git reset --hard HEAD~1

    # Setup Server Script
    cat << 'EOF' > /home/user/service_repo/server.py
from flask import Flask, jsonify, request
import math

app = Flask(__name__)

class Metrics:
    def __init__(self):
        self.count = 0
        self.mean = 0.0
        self.m2 = 0.0

    def update(self, value):
        self.count += 1
        delta = value - self.mean
        self.mean += delta / self.count
        delta2 = value - self.mean
        self.m2 += delta * delta2

    def get_variance(self):
        if self.count < 2:
            return 0.0
        return self.m2 / (self.count - 1)

metrics = Metrics()

@app.route('/api/metrics', methods=['POST'])
def add_metric():
    val = request.json.get('value', 0)
    metrics.update(float(val))
    return jsonify({"status": "ok"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)
EOF

    # Finalize user
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user /app

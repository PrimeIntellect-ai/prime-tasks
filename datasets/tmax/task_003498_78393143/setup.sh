#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        redis-server \
        libhiredis-dev \
        nginx \
        build-essential \
        curl
    pip3 install pytest flask redis pandas

    mkdir -p /app

    # Create references and golden output
    cat << 'EOF' > /app/generate_data.py
import random
import math
import csv

random.seed(42)

# Generate references
refs = []
for i in range(10):
    refs.append([f"ref_{i}"] + [random.uniform(-50, 50) for _ in range(5)])

with open("/app/references.csv", "w", newline="") as f:
    writer = csv.writer(f)
    for r in refs:
        writer.writerow([r[0]] + [round(x, 2) for x in r[1:]])

# Generate golden output
golden = []
for i in range(1000):
    record_id = f"rec_{i}"

    # Generate raw values
    raw_vals = []
    for _ in range(5):
        if random.random() < 0.1:
            raw_vals.append("NaN")
        else:
            raw_vals.append(random.uniform(-60, 60))

    # Process
    valid_vals = [v for v in raw_vals if v != "NaN"]
    if not valid_vals:
        mean_val = 0.0
    else:
        mean_val = sum(valid_vals) / len(valid_vals)

    cleaned_vals = []
    for v in raw_vals:
        val = mean_val if v == "NaN" else v
        # Clamp
        val = max(-50.0, min(50.0, val))
        cleaned_vals.append(val)

    # Find closest ref
    min_dist = float('inf')
    closest_ref = None
    for r in refs:
        dist = math.sqrt(sum((c - rv)**2 for c, rv in zip(cleaned_vals, r[1:])))
        if dist < min_dist:
            min_dist = dist
            closest_ref = r[0]

    if min_dist < 20.0:
        golden.append([record_id] + [round(x, 2) for x in cleaned_vals] + [closest_ref])

with open("/app/golden_output.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerows(golden)
EOF
    python3 /app/generate_data.py

    # Create nginx.conf with deliberate typo
    cat << 'EOF' > /app/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://localhost:5001;
        }
    }
}
EOF

    # Create api.py with deliberate typo
    cat << 'EOF' > /app/api.py
from flask import Flask, request
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6380)

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.json.get('payload')
    if data:
        r.rpush('sensor_queue', data)
        return "OK", 200
    return "Error", 400

if __name__ == '__main__':
    app.run(port=5000)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

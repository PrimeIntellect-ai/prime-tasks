#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        redis-server

    pip3 install --no-cache-dir pytest flask redis numpy requests

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/log_pipeline/output

    cat << 'EOF' > /home/user/log_pipeline/start_services.sh
#!/bin/bash
mkdir -p /home/user/log_pipeline/output
redis-server --daemonize yes
nohup python3 /home/user/log_pipeline/app.py > /home/user/log_pipeline/app.log 2>&1 &
nohup python3 /home/user/log_pipeline/worker.py > /home/user/log_pipeline/worker.log 2>&1 &
echo "Services started"
EOF
    chmod +x /home/user/log_pipeline/start_services.sh

    cat << 'EOF' > /home/user/log_pipeline/app.py
from flask import Flask, request, jsonify
import redis
import json

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "ok"})

@app.route('/logs', methods=['POST'])
def receive_logs():
    data = request.json
    if not isinstance(data, list):
        data = [data]
    for item in data:
        r.lpush('log_queue', json.dumps(item))
    return jsonify({"status": "queued", "count": len(data)})

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /home/user/log_pipeline/worker.py
import redis
import json
import time
import numpy as np
import os

r = redis.Redis(host='localhost', port=6379, db=0)
OUTPUT_FILE = '/home/user/log_pipeline/output/metrics.json'

def process_batch():
    batch = []
    while True:
        item = r.rpop('log_queue')
        if not item:
            break
        batch.append(json.loads(item))

    if not batch:
        return

    ids = [b['id'] for b in batch]
    # BUG: using int32 causes overflow with ms timestamps
    starts = np.array([b['start_ts'] for b in batch], dtype=np.int32)
    ends = np.array([b['end_ts'] for b in batch], dtype=np.int32)

    latencies = ends - starts

    with open(OUTPUT_FILE, 'a') as f:
        for i, req_id in enumerate(ids):
            # Only record if latency seems somewhat valid to simulate dropping bad records
            if latencies[i] >= 0:
                f.write(json.dumps({"id": req_id, "latency": int(latencies[i])}) + '\n')

if __name__ == '__main__':
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    while True:
        process_batch()
        time.sleep(1)
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user

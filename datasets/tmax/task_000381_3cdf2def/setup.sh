#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest flask redis

    mkdir -p /app

    # Create emitter.py
    cat << 'EOF' > /app/emitter.py
import time
import json
import uuid
import random
import redis

r = redis.Redis(host='localhost', port=6379, db=0)
services = ['payment-service', 'auth-service', 'user-service']
valid_levels = ['INFO', 'WARN', 'CRITICAL']
invalid_levels = ['DEBUG', 'FATAL']

while True:
    for _ in range(100):
        is_valid = random.random() > 0.2
        is_critical = is_valid and random.random() < 0.1

        log = {
            'id': str(uuid.uuid4()) if is_valid else 'invalid-uuid',
            'timestamp': time.time(),
            'service': random.choice(services),
            'level': 'CRITICAL' if is_critical else (random.choice(valid_levels) if is_valid else random.choice(invalid_levels)),
            'msg': 'log message'
        }
        r.lpush('raw_logs', json.dumps(log))
    time.sleep(0.1)
EOF

    # Create api.py
    cat << 'EOF' > /app/api.py
from flask import Flask, jsonify
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0, decode_responses=True)

@app.route('/metrics')
def metrics():
    counts = r.hgetall('metrics:counts')
    counts = {k: int(v) for k, v in counts.items()}
    return jsonify(counts)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    chmod +x /app/emitter.py /app/api.py
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

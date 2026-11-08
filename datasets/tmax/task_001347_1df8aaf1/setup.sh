#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server
pip3 install pytest flask redis requests scipy

mkdir -p /home/user/services/emitter
mkdir -p /home/user/services/analyzer

cat << 'EOF' > /home/user/services/emitter/config.env
REDIS_PORT=6380
EOF

cat << 'EOF' > /home/user/services/analyzer/config.env
REDIS_PORT=6380
PROCESSOR_PATH=
EOF

cat << 'EOF' > /home/user/services/emitter/app.py
import os, json, random
from flask import Flask, jsonify
import redis

app = Flask(__name__)

def get_redis_port():
    with open('config.env') as f:
        for line in f:
            if line.startswith('REDIS_PORT='):
                return int(line.strip().split('=')[1])
    return 6379

@app.route('/generate', methods=['GET'])
def generate():
    port = get_redis_port()
    r = redis.Redis(host='127.0.0.1', port=port)
    for _ in range(5):
        signal = [random.uniform(-1000.0, 1000.0) for _ in range(100)]
        r.lpush('signals', json.dumps(signal))
    return jsonify({"status": "ok"})

if __name__ == '__main__':
    app.run(port=5000)
EOF

cat << 'EOF' > /home/user/services/analyzer/app.py
import os, json, subprocess, math
from flask import Flask, jsonify
import redis
import requests

app = Flask(__name__)

def get_config():
    config = {}
    with open('config.env') as f:
        for line in f:
            if '=' in line:
                k, v = line.strip().split('=', 1)
                config[k] = v
    return config

@app.route('/analyze', methods=['GET'])
def analyze():
    config = get_config()
    port = int(config.get('REDIS_PORT', 6380))
    processor_path = config.get('PROCESSOR_PATH', '')

    requests.get('http://127.0.0.1:5000/generate')

    r = redis.Redis(host='127.0.0.1', port=port)
    empirical_sums = []
    baseline_sums = []

    for _ in range(5):
        item = r.rpop('signals')
        if not item:
            continue
        signal = json.loads(item)

        proc = subprocess.run([processor_path], input=" ".join(map(str, signal)), text=True, capture_output=True)
        try:
            val = float(proc.stdout.strip())
            empirical_sums.append(val)
        except:
            empirical_sums.append(0.0)

        baseline_sums.append(math.fsum(signal))

    kl = 0.0
    for e, b in zip(empirical_sums, baseline_sums):
        kl += abs(e - b)

    return jsonify({"status": "ok", "kl_divergence": kl})

if __name__ == '__main__':
    app.run(port=5001)
EOF

mkdir -p /app
cat << 'EOF' > /app/oracle_processor
#!/usr/bin/env python3
import sys
import math
data = sys.stdin.read().split()
nums = [float(x) for x in data]
print(f"{math.fsum(nums):.6f}")
EOF
chmod +x /app/oracle_processor

# Ensure redis starts when bash is invoked for tests
echo "redis-server --daemonize yes" >> /etc/bash.bashrc

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

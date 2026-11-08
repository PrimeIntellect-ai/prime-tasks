#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        g++ \
        libcurl4-openssl-dev \
        redis-server \
        redis-tools \
        curl

    pip3 install --default-timeout=100 pytest flask redis

    mkdir -p /app/services/flask_service
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --port 6380 --daemonize yes
cd /app/services/flask_service
nohup python3 app.py > flask.log 2>&1 &
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/services/flask_service/config.json
{
  "redis_host": "127.0.0.1",
  "redis_port": 6379
}
EOF

    cat << 'EOF' > /app/services/flask_service/app.py
import json
import redis
from flask import Flask, jsonify

app = Flask(__name__)

with open('config.json') as f:
    config = json.load(f)

r = redis.Redis(host=config['redis_host'], port=config['redis_port'], decode_responses=True)

@app.route('/threshold')
def get_threshold():
    try:
        val = r.get('threshold')
        if val is None:
            return jsonify({"error": "not found"}), 404
        return jsonify({"threshold": float(val)})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /tmp/generate_corpus.py
import os
import random

for i in range(10):
    with open(f'/app/corpus/clean/data_{i}.csv', 'w') as f:
        f.write('id,val_X,val_Y,val_Z\n')
        for j in range(100):
            x = random.gauss(0, 1)
            y = random.gauss(0, 1)
            z = random.gauss(0, 1)
            f.write(f'{j},{x},{y},{z}\n')

for i in range(10):
    with open(f'/app/corpus/evil/data_{i}.csv', 'w') as f:
        f.write('id,val_X,val_Y,val_Z\n')
        for j in range(100):
            x = random.gauss(0, 1)
            y = 2.0 * x + random.gauss(0, 0.1)
            z = random.gauss(0, 1)
            f.write(f'{j},{x},{y},{z}\n')
EOF
    python3 /tmp/generate_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

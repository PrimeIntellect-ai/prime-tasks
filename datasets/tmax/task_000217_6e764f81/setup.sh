#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl
    pip3 install --no-cache-dir pytest Flask redis numpy scipy requests

    mkdir -p /app/sensor_api

    cat << 'EOF' > /app/sensor_api/app.py
import os
import json
import numpy as np
from flask import Flask, jsonify
import redis

app = Flask(__name__)
redis_url = os.environ.get('REDIS_URL')

if not redis_url:
    raise ValueError("REDIS_URL environment variable is not set")

r = redis.Redis.from_url(redis_url)

@app.route('/data')
def get_data():
    x = np.linspace(0, 10, 150)
    y = 2.5 * np.exp(-0.1 * x) + 4.0 * np.sin(1.5 * x)
    np.random.seed(42)
    y += np.random.normal(0, 0.2, size=x.shape)
    return jsonify({'x': x.tolist(), 'y': y.tolist()})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes

# TODO: Fix the configuration so the Flask API can connect to Redis
# The Flask API expects REDIS_URL to be set.

python3 /app/sensor_api/app.py &
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        redis-server \
        libcurl4-openssl-dev \
        g++ \
        curl

    pip3 install pytest flask redis scipy numpy

    mkdir -p /app
    cat << 'EOF' > /app/ingestion.py
from flask import Flask, request
import redis, json

app = Flask(__name__)
# BUG 1: Port is 6380 instead of 6379
r = redis.Redis(host='127.0.0.1', port=6380, db=0)

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.json
    r.rpush('graph_metrics', json.dumps(data))
    return "OK"

if __name__ == '__main__':
    # BUG 2: Bound to wrong host causing connection refused from localhost client
    app.run(host='192.168.1.1', port=8000)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

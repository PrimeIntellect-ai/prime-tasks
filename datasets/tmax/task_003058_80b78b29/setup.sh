#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server nginx curl jq
    pip3 install pytest flask redis

    mkdir -p /app/services/api
    mkdir -p /app/services/nginx
    mkdir -p /app/data/clean
    mkdir -p /app/data/evil

    for i in 1 2 3 4 5; do
        echo ">clean_$i" > /app/data/clean/clean_$i.fasta
        echo "ACGTACGT" >> /app/data/clean/clean_$i.fasta
    done

    for i in 1 2 3 4 5; do
        echo ">evil_$i" > /app/data/evil/evil_$i.fasta
        echo "GCGCGCGC" >> /app/data/evil/evil_$i.fasta
    done

    cat << 'EOF' > /app/services/api/app.py
from flask import Flask, request, jsonify
import redis
import os

app = Flask(__name__)
# Broken redis config
r = redis.Redis(host='redis', port=6379, db=0)

@app.route('/score', methods=['POST'])
def score():
    data = request.get_json()
    seq = data.get('sequence', '')
    # Simulate redis usage
    r.ping()
    if 'GCGC' in seq:
        return jsonify({"score": 0.1, "converged": True})
    return jsonify({"score": 0.9, "converged": True})

if __name__ == '__main__':
    # Misconfigured port
    app.run(host='0.0.0.0', port=5001)
EOF

    cat << 'EOF' > /app/services/nginx/nginx.conf
events {}
http {
    upstream backend {
        server backend:80;
    }
    server {
        listen 80;
        location / {
            proxy_pass http://backend;
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

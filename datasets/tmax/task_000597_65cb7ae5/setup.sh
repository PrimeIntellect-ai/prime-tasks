#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest flask redis

    mkdir -p /app/messy_files
    mkdir -p /app/nginx
    mkdir -p /app/api

    cat << 'EOF' > /app/messy_files/nginx.prod.bak
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://backend.example.com:80;
        }
    }
}
EOF

    cat << 'EOF' > /app/messy_files/app.py.bak
import os
from flask import Flask, jsonify
import redis

app = Flask(__name__)

DB_HOST = "redis.prod.internal"
ENV = "production"

@app.route('/health')
def health():
    try:
        r = redis.Redis(host=DB_HOST, port=6379, socket_timeout=1)
        ping_res = r.ping()
    except Exception as e:
        ping_res = False
    return jsonify({"status": "ok", "env": ENV, "redis_ping": ping_res})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

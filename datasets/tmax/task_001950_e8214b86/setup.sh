#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest flask

    mkdir -p /app

    cat << 'EOF' > /app/nginx.conf
events {
    worker_connections 1024;
}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:5001; # INTENTIONAL ERROR
        }
    }
}
EOF

    cat << 'EOF' > /app/app.py
from flask import Flask, jsonify
import sys

app = Flask(__name__)

@app.route('/')
def index():
    return jsonify({"status": "ok"})

@app.route('/health')
def health():
    return jsonify({"health": "good"})

if __name__ == '__main__':
    # INTENTIONAL ERROR: bind to 127.0.0.1 but port is missing or wrong
    app.run(host='127.0.0.1', por=5000)
EOF

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

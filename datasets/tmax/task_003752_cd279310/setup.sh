#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest Flask redis gunicorn

    mkdir -p /app/nginx

    cat << 'EOF' > /app/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            # BROKEN: missing proxy_pass
            # proxy_pass http://localhost:5000;
        }
    }
}
EOF

    cat << 'EOF' > /app/app.py
from flask import Flask, request, jsonify
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/ingest', methods=['POST'])
def ingest():
    # Naive broken parser
    data = request.get_data(as_text=True)
    lines = data.split('\n')
    for line in lines:
        if line.strip():
            # Broken unicode parsing, no deduplication, etc.
            pass
    return "OK", 200

@app.route('/metrics', methods=['GET'])
def metrics():
    start = request.args.get('start')
    end = request.args.get('end')
    # Not implemented
    return jsonify([])

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /app/requirements.txt
Flask
redis
gunicorn
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

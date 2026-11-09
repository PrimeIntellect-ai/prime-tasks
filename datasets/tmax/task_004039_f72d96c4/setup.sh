#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx redis-server
pip3 install pytest flask redis

mkdir -p /workspace/system
mkdir -p /workspace/data

cat << 'EOF' > /workspace/system/flask_app.py
from flask import Flask, request
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.data.decode('utf-8', errors='replace')
    r.rpush('raw_data', data)
    return 'OK', 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

cat << 'EOF' > /workspace/system/nginx.conf
worker_processes 1;
daemon off;

events {
    worker_connections 1024;
}

http {
    server {
        listen 8080;
        server_name localhost;

        # The proxy configuration is missing
        # location /ingest {
        #     proxy_pass http://127.0.0.1:5000;
        # }
    }
}
EOF

cat << 'EOF' > /workspace/data/clean.jsonl
{"id": 1, "group": "A", "probabilities": [0.5, 0.5], "value": 10.0}
{"id": 2, "group": "B", "probabilities": [0.2, 0.8], "value": 5.0}
{"id": 3, "group": "A", "probabilities": [0.1, 0.9], "value": 0.0}
{"id": 4, "group": "C", "probabilities": [1.0], "value": 20.0}
{"id": 5, "group": "B", "probabilities": [0.3, 0.7], "value": 1.0}
{"id": 6, "group": "D", "probabilities": [0.4, 0.6], "value": 2.0}
{"id": 7, "group": "A", "probabilities": [0.5, 0.5], "value": 3.0}
{"id": 8, "group": "C", "probabilities": [0.0, 1.0], "value": 4.0}
{"id": 9, "group": "D", "probabilities": [0.5, 0.5], "value": 5.0}
{"id": 10, "group": "E", "probabilities": [0.1, 0.9], "value": 6.0}
{"id": 11, "group": "A", "probabilities": [0.5, 0.5], "value": 7.0}
{"id": 12, "group": "B", "probabilities": [0.2, 0.8], "value": 8.0}
{"id": 13, "group": "A", "probabilities": [0.1, 0.9], "value": 9.0}
{"id": 14, "group": "C", "probabilities": [1.0], "value": 10.0}
{"id": 15, "group": "B", "probabilities": [0.3, 0.7], "value": 11.0}
{"id": 16, "group": "D", "probabilities": [0.4, 0.6], "value": 12.0}
{"id": 17, "group": "A", "probabilities": [0.5, 0.5], "value": 13.0}
{"id": 18, "group": "C", "probabilities": [0.0, 1.0], "value": 14.0}
{"id": 19, "group": "D", "probabilities": [0.5, 0.5], "value": 15.0}
{"id": 20, "group": "E", "probabilities": [0.1, 0.9], "value": 16.0}
EOF

cat << 'EOF' > /workspace/data/evil.jsonl
{"id": 101, "group": "bad\u", "probabilities": [0.5, 0.5], "value": 10.0}
{"id": 102, "group": "A", "probabilities": [0.5, 0.6], "value": 5.0}
{"id": 103, "group": "B", "probabilities": [0.5, 0.5], "value": -1.0}
{"id": 104, "group": "bad\u", "probabilities": [0.5, 0.6], "value": -1.0}
{"id": 105, "group": "C", "probabilities": [1.0, 0.1], "value": 20.0}
{"id": 106, "group": "D", "probabilities": [0.4, 0.4], "value": 2.0}
{"id": 107, "group": "bad\u", "probabilities": [0.5, 0.5], "value": 3.0}
{"id": 108, "group": "C", "probabilities": [0.0, 0.9], "value": 4.0}
{"id": 109, "group": "D", "probabilities": [0.5, 0.5], "value": -5.0}
{"id": 110, "group": "E", "probabilities": [0.1, 0.8], "value": 6.0}
{"id": 111, "group": "bad\u", "probabilities": [0.5, 0.5], "value": 7.0}
{"id": 112, "group": "B", "probabilities": [0.2, 0.9], "value": 8.0}
{"id": 113, "group": "A", "probabilities": [0.1, 0.9], "value": -9.0}
{"id": 114, "group": "C", "probabilities": [1.1], "value": 10.0}
{"id": 115, "group": "B", "probabilities": [0.3, 0.7], "value": -11.0}
{"id": 116, "group": "D", "probabilities": [0.4, 0.7], "value": 12.0}
{"id": 117, "group": "bad\u", "probabilities": [0.5, 0.5], "value": 13.0}
{"id": 118, "group": "C", "probabilities": [0.0, 1.0], "value": -14.0}
{"id": 119, "group": "D", "probabilities": [0.5, 0.6], "value": 15.0}
{"id": 120, "group": "E", "probabilities": [0.1, 0.9], "value": -16.0}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /workspace
chmod -R 777 /home/user

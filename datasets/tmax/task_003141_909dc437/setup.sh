#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        jq \
        util-linux \
        nginx \
        redis-server \
        curl

    pip3 install pytest flask redis requests

    useradd -m -s /bin/bash user || true

    mkdir -p /app/api
    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean
    mkdir -p /app/tests
    mkdir -p /home/user/nginx
    mkdir -p /home/user/staging
    mkdir -p /home/user/archive/blobs

    # Create intake.py
    cat << 'EOF' > /app/api/intake.py
import os
import uuid
import tarfile
from flask import Flask, request, jsonify
import redis

app = Flask(__name__)
redis_host = "invalid-host"
r = redis.Redis(host=redis_host, port=6379, db=0)

@app.route('/upload', methods=['POST'])
def upload():
    if 'file' not in request.files:
        return jsonify({'error': 'No file part'}), 400
    file = request.files['file']
    if file.filename == '':
        return jsonify({'error': 'No selected file'}), 400

    uid = str(uuid.uuid4())
    staging_dir = f"/home/user/staging/{uid}"
    os.makedirs(staging_dir, exist_ok=True)

    tar_path = os.path.join(staging_dir, "upload.tar")
    file.save(tar_path)

    try:
        with tarfile.open(tar_path, "r:*") as tar:
            tar.extractall(path=staging_dir)
        os.remove(tar_path)
    except Exception as e:
        pass

    try:
        r.lpush('intake_queue', staging_dir)
    except Exception as e:
        return jsonify({'error': 'Redis connection failed'}), 500

    return jsonify({'message': 'Uploaded', 'uuid': uid}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8081)
EOF

    # Create nginx.conf
    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
pid /tmp/nginx.pid;
events {
    worker_connections 1024;
}
http {
    client_body_temp_path /tmp/client_temp;
    proxy_temp_path       /tmp/proxy_temp_path;
    fastcgi_temp_path     /tmp/fastcgi_temp;
    uwsgi_temp_path       /tmp/uwsgi_temp;
    scgi_temp_path        /tmp/scgi_temp;

    client_max_body_size 1m;
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:8081;
        }
    }
}
EOF

    # Create verification script
    cat << 'EOF' > /app/tests/run_verification.py
import os
import time
import requests
import json
import glob

def run():
    print("Running verification...")

if __name__ == "__main__":
    run()
EOF

    # Create dummy corpus files
    touch /app/corpus/evil/dummy.tar
    touch /app/corpus/clean/dummy.tar

    chmod -R 777 /home/user
    chmod -R 777 /app

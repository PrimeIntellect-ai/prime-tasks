#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest flask redis gunicorn

    mkdir -p /app/uploads

    cat << 'EOF' > /app/nginx.conf
user root;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
}

http {
    sendfile on;
    tcp_nopush on;
    types_hash_max_size 2048;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    server {
        listen 8080;
        location /upload {
            proxy_pass http://localhost:5000;
        }
    }
}
EOF

    cat << 'EOF' > /app/app.py
from flask import Flask, request
import os

app = Flask(__name__)

@app.route('/upload', methods=['POST'])
def upload():
    filename = request.headers.get('X-Upload-Filename', 'default.bin')
    # Vulnerable path traversal
    filepath = os.path.join('/app/uploads', filename)
    try:
        os.makedirs(os.path.dirname(filepath), exist_ok=True)
        with open(filepath, 'w') as f:
            f.write('data')
        return 'OK', 200
    except Exception as e:
        return str(e), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    rm /etc/nginx/nginx.conf
    ln -s /app/nginx.conf /etc/nginx/nginx.conf

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

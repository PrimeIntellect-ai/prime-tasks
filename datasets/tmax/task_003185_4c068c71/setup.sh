#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx gawk curl
    pip3 install pytest flask gunicorn

    # Create necessary directories
    mkdir -p /home/user/nginx
    mkdir -p /home/user/vfs
    mkdir -p /home/user/data/finops_volume
    mkdir -p /home/user/app

    # Create Nginx configuration
    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
daemon off;
error_log /home/user/nginx/error.log;
pid /home/user/nginx/nginx.pid;
events { worker_connections 1024; }
http {
    server {
        listen 8080;
        location / {
            # Intentionally broken path
            proxy_pass http://unix:/tmp/wrong_path.sock;
        }
    }
}
EOF

    # Create fstab file
    cat << 'EOF' > /home/user/vfs/fstab
UUID=a1b2c3d4 /home/user/data/archive ext4 defaults 0 2
UUID=9f8e7d6c /home/user/data/finops_volume ext4 defaults,finops=true,rw 0 2
UUID=5a4b3c2d /home/user/data/logs xfs defaults 0 0
EOF

    # Create billing log
    cat << 'EOF' > /home/user/data/finops_volume/billing.log
2023-10-01T12:00:00Z|EC2|i-123456|10.50
2023-10-01T12:05:00Z|S3|bucket-a|2.25
2023-10-01T12:10:00Z|EC2|i-987654|5.00
2023-10-01T12:15:00Z|RDS|db-1|15.00
2023-10-01T12:20:00Z|S3|bucket-b|1.75
EOF

    # Create Python API stub
    cat << 'EOF' > /home/user/app/api.py
from flask import Flask, jsonify
import subprocess

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({"status": "ok"})

@app.route('/metrics')
def metrics():
    # TODO: Implement
    pass
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

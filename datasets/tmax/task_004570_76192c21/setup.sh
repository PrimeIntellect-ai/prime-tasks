#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server nginx openssh-server curl sudo gawk sed grep
    pip3 install pytest flask redis python-dotenv

    useradd -m -s /bin/bash user || true

    mkdir -p /run/sshd
    ssh-keygen -A

    # Set up SSH for user
    su - user -c "mkdir -p ~/.ssh && ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa"
    su - user -c "cp ~/.ssh/id_rsa.pub ~/.ssh/authorized_keys"
    su - user -c "ssh-keyscan localhost >> ~/.ssh/known_hosts 2>/dev/null"
    su - user -c "ssh-keyscan 127.0.0.1 >> ~/.ssh/known_hosts 2>/dev/null"

    # Create monitoring stack
    mkdir -p /home/user/monitoring_stack/api

    cat << 'EOF' > /home/user/monitoring_stack/nginx.conf
events {
    worker_connections 1024;
}
http {
    server {
        listen 8080;
        location /api/ {
            # proxy_pass is missing
        }
    }
}
EOF

    cat << 'EOF' > /home/user/monitoring_stack/redis.conf
port 6379
bind 127.0.0.1
daemonize no
EOF

    cat << 'EOF' > /home/user/monitoring_stack/api/.env
REDIS_URL=redis://127.0.0.1:9999/0
EOF

    cat << 'EOF' > /home/user/monitoring_stack/api/app.py
import os
import redis
from flask import Flask, jsonify
from dotenv import load_dotenv

load_dotenv()
app = Flask(__name__)
redis_url = os.getenv("REDIS_URL", "redis://127.0.0.1:9999/0")
r = redis.from_url(redis_url)

@app.route('/api/health')
def health():
    try:
        r.ping()
        return jsonify({"status": "ok", "redis": "connected"}), 200
    except Exception as e:
        return jsonify({"status": "error", "redis": "disconnected", "error": str(e)}), 500

@app.route('/api/metrics')
def metrics():
    return jsonify({"metrics": "sample"}), 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create corpus directories and files
    mkdir -p /home/user/corpus/clean /home/user/corpus/evil /home/user/corpus/clean_hidden /home/user/corpus/evil_hidden

    cat << 'EOF' > /home/user/corpus/clean/log1.txt
127.0.0.1 - - [10/Oct/2023:13:55:36 -0700] "GET /api/health HTTP/1.1" 200 42 "-" "Prometheus/2.30"
127.0.0.1 - - [10/Oct/2023:13:55:40 -0700] "GET /api/metrics HTTP/1.1" 200 55 "-" "Datadog Agent"
EOF

    cat << 'EOF' > /home/user/corpus/evil/log1.txt
127.0.0.1 - - [10/Oct/2023:13:56:01 -0700] "GET /api/health?id=1' OR '1'='1 HTTP/1.1" 200 42 "-" "curl/7.68.0"
127.0.0.1 - - [10/Oct/2023:13:56:05 -0700] "POST /api/health HTTP/1.1" 405 120 "-" "Nmap Scripting Engine"
127.0.0.1 - - [10/Oct/2023:13:56:10 -0700] "GET /api/health/../../etc/passwd HTTP/1.1" 400 12 "-" "Mozilla/5.0"
EOF

    cp /home/user/corpus/clean/log1.txt /home/user/corpus/clean_hidden/log1.txt
    cat << 'EOF' >> /home/user/corpus/clean_hidden/log1.txt
127.0.0.1 - - [10/Oct/2023:13:55:45 -0700] "GET /api/health HTTP/1.1" 200 42 "-" "CustomMonitor/1.0"
EOF

    cp /home/user/corpus/evil/log1.txt /home/user/corpus/evil_hidden/log1.txt
    cat << 'EOF' >> /home/user/corpus/evil_hidden/log1.txt
127.0.0.1 - - [10/Oct/2023:13:56:15 -0700] "GET /api/health?q=<script>alert(1)</script> HTTP/1.1" 200 42 "-" "curl/7.68.0"
127.0.0.1 - - [10/Oct/2023:13:56:20 -0700] "PUT /api/metrics HTTP/1.1" 405 120 "-" "Nmap Scripting Engine"
EOF

    # Ensure permissions are set properly
    chmod -R 777 /home/user

    # Fix SSH permissions (SSH is strict about permissions)
    chmod 700 /home/user/.ssh
    chmod 600 /home/user/.ssh/id_rsa
    chmod 644 /home/user/.ssh/id_rsa.pub
    chmod 600 /home/user/.ssh/authorized_keys
    chmod 644 /home/user/.ssh/known_hosts
    chown -R user:user /home/user/.ssh

    # Ensure sshd is running in the background for tests that execute immediately
    echo "service ssh start" >> /home/user/.bashrc

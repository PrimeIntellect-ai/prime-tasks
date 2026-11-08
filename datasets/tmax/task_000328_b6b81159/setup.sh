#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest flask gunicorn redis requests aiohttp

    mkdir -p /app/nginx /app/api /home/user

    cat << 'EOF' > /app/nginx/nginx.conf
worker_processes 1;
daemon off;
events {
    worker_connections 1024;
}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:5001;
        }
    }
}
EOF

    cat << 'EOF' > /app/api/app.py
from flask import Flask, jsonify
import random
import time
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/health')
def health():
    if random.random() < 0.15:
        time.sleep(2.0)

    db_status = "connected"
    if random.random() < 0.15:
        db_status = "disconnected"

    return jsonify({"status": "ok", "db_status": db_status})
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
gunicorn --chdir /app/api -w 4 -b 127.0.0.1:5000 app:app --daemon
nginx -c /app/nginx/nginx.conf &
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /home/user/monitor.py
import requests
import json
import time

def run_monitor():
    total_requests = 100
    successful = 0
    failed = 0

    for _ in range(total_requests):
        resp = requests.get("http://127.0.0.1:8080/health", timeout=1)
        if resp.status_code == 200:
            successful += 1
        else:
            failed += 1

    with open("/home/user/report.json", "w") as f:
        json.dump({
            "total_requests": total_requests,
            "successful_requests": successful,
            "failed_requests": failed
        }, f, indent=2)

if __name__ == "__main__":
    run_monitor()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /app /home/user
    chmod -R 777 /home/user

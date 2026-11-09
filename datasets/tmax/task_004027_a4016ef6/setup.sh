#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        jq \
        gawk \
        sed \
        nginx \
        redis-server \
        curl

    pip3 install pytest flask redis

    mkdir -p /home/user/data/raw_configs
    mkdir -p /home/user/app
    mkdir -p /home/user/scripts

    # Generate 5000 JSON files
    cat << 'EOF' > /tmp/generate_configs.py
import json
import random
import os

os.makedirs('/home/user/data/raw_configs', exist_ok=True)
timestamp = 1670000000
services = ["api_gateway", "auth_service", "payment_service"]

for i in range(5000):
    timestamp += random.randint(1, 5)
    data = {
        "timestamp": str(timestamp),
        "service": random.choice(services),
        "config": {
            "rate_limit": random.choice([100, 200, 500]),
            "timeout": random.choice([10, 30, 60])
        }
    }
    with open(f'/home/user/data/raw_configs/config_{i:04d}.json', 'w') as f:
        json.dump(data, f, indent=2)
EOF
    python3 /tmp/generate_configs.py
    rm /tmp/generate_configs.py

    # Create start_services.sh
    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
export COMPRESSED_DATA_PATH=/home/user/data/configs.dat
export DECOMPRESS_SCRIPT=/home/user/scripts/decompress.py
python3 /home/user/app/app.py &
nginx -c /home/user/app/nginx.conf
EOF
    chmod +x /home/user/app/start_services.sh

    # Create nginx.conf
    cat << 'EOF' > /home/user/app/nginx.conf
worker_processes 1;
daemon off;
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
    access_log /tmp/access.log;
    error_log /tmp/error.log;

    server {
        listen 8080;
        location / {
            # proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    # Create app.py
    cat << 'EOF' > /home/user/app/app.py
import os
import subprocess
from flask import Flask, Response
import redis

app = Flask(__name__)
cache = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/history')
def history():
    cached = cache.get('history')
    if cached:
        return Response(cached, mimetype='text/csv')

    script = os.environ.get('DECOMPRESS_SCRIPT')
    data_path = os.environ.get('COMPRESSED_DATA_PATH')

    if not script or not data_path or not os.path.exists(script) or not os.path.exists(data_path):
        return "Missing script or data", 500

    try:
        result = subprocess.run(['python3', script], capture_output=True, text=True, check=True)
        csv_data = result.stdout
        cache.set('history', csv_data)
        return Response(csv_data, mimetype='text/csv')
    except Exception as e:
        return str(e), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

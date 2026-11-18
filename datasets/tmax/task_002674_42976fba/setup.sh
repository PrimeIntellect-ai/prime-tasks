#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        redis-server \
        libhiredis-dev \
        nlohmann-json3-dev \
        nginx \
        g++ \
        make \
        curl

    pip3 install --no-cache-dir --default-timeout=100 pytest flask redis numpy

    mkdir -p /app/data/clean
    mkdir -p /app/data/evil
    mkdir -p /home/user

    # Flask app
    cat << 'EOF' > /app/app.py
from flask import Flask, request, jsonify
import redis
import json

app = Flask(__name__)
r = redis.Redis(host='127.0.0.1', port=6379, db=0)

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.json
    if data:
        r.rpush('incoming_queue', json.dumps(data))
        return jsonify({"status": "queued"}), 200
    return jsonify({"error": "No data"}), 400

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Start services script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/app.py &
EOF
    chmod +x /app/start_services.sh

    # Nginx config (incomplete/incorrect)
    cat << 'EOF' > /home/user/nginx.conf
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

    server {
        listen 8080;

        # TODO: Route /api/ to the Flask app on port 5000
        location /api/ {
            return 404;
        }
    }
}
EOF

    # Generate data
    cat << 'EOF' > /app/generate_data.py
import os
import json
import numpy as np

np.random.seed(42)

for i in range(100):
    a = float(np.random.normal(50.0, 5.0))
    b = float(np.random.normal(100.0, 10.0))
    c = float(0.5 * a + 0.8 * b + np.random.normal(0.0, 2.0))
    with open(f'/app/data/clean/item_{i}.json', 'w') as f:
        json.dump({"id": f"clean_{i}", "a": a, "b": b, "c": c}, f)

for i in range(100):
    a = float(np.random.normal(50.0, 5.0))
    b = float(np.random.normal(100.0, 10.0))
    # Evil offset
    c = float(0.5 * a + 0.8 * b + np.random.normal(50.0, 5.0))
    with open(f'/app/data/evil/item_{i}.json', 'w') as f:
        json.dump({"id": f"evil_{i}", "a": a, "b": b, "c": c}, f)
EOF
    python3 /app/generate_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app

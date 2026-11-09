#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl jq
    pip3 install pytest flask gunicorn redis python-dotenv

    mkdir -p /app/nginx
    mkdir -p /app/flask
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create Nginx config (broken)
    cat << 'EOF' > /app/nginx/nginx.conf
worker_processes 1;
daemon off;
events { worker_connections 1024; }
http {
    server {
        listen 8080;
        location / {
            return 404;
        }
        # TODO: Add location /intake to proxy requests to Flask at 127.0.0.1:5000
    }
}
EOF

    # Create Flask .env (broken)
    cat << 'EOF' > /app/flask/.env
REDIS_HOST=remote.internal.net
REDIS_PORT=6379
EOF

    # Create Flask sanitizer.py (broken)
    cat << 'EOF' > /app/flask/sanitizer.py
def check_cycles(node, graph):
    # BUG: No visited tracking, will cause RecursionError on cycles
    if node not in graph:
        return True
    for child in graph[node]:
        if not check_cycles(child, graph):
            return False
    return True

def validate(payload):
    try:
        # BUG: Float casting causes precision loss for large nanosecond integers
        if float(payload['end_ns']) - float(payload['start_ns']) != float(payload['duration_ns']):
            return False
    except (KeyError, ValueError):
        return False

    tree = payload.get('component_tree', {})
    for node in tree:
        try:
            if not check_cycles(node, tree):
                return False
        except RecursionError:
            # Let it crash or return False? The instructions say it crashes on edge cases.
            # We will just let it raise or we can catch and raise.
            raise

    return True
EOF

    # Create Flask app.py
    cat << 'EOF' > /app/flask/app.py
import os
import json
from flask import Flask, request, jsonify
import redis
from dotenv import load_dotenv
from sanitizer import validate

load_dotenv()

app = Flask(__name__)

r = redis.Redis(host=os.getenv('REDIS_HOST', 'localhost'), port=int(os.getenv('REDIS_PORT', 6379)), db=0)

@app.route('/intake', methods=['POST'])
def intake():
    payload = request.json
    if not payload:
        return jsonify({"error": "No payload"}), 400

    try:
        if not validate(payload):
            return jsonify({"error": "Invalid payload"}), 400
    except RecursionError:
        return jsonify({"error": "RecursionError"}), 500

    try:
        r.rpush('uptime_metrics', json.dumps(payload))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

    return jsonify({"status": "ok"}), 200

if __name__ == '__main__':
    app.run(port=5000)
EOF

    # Create start_all.sh
    cat << 'EOF' > /app/start_all.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/nginx/nginx.conf &
cd /app/flask && gunicorn -w 1 -b 127.0.0.1:5000 app:app &
wait
EOF
    chmod +x /app/start_all.sh

    # Generate corpus
    python3 -c "
import json
import os

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

# Clean corpus
for i in range(20):
    start = 1600000000000000000 + i * 1000000
    duration = 5000000
    end = start + duration
    payload = {
        'start_ns': str(start),
        'end_ns': str(end),
        'duration_ns': str(duration),
        'component_tree': {'A': ['B'], 'B': ['C']}
    }
    with open(f'/app/corpus/clean/clean_{i}.json', 'w') as f:
        json.dump(payload, f)

# Evil corpus - Cycles
for i in range(10):
    start = 1600000000000000000 + i * 1000000
    duration = 5000000
    end = start + duration
    payload = {
        'start_ns': str(start),
        'end_ns': str(end),
        'duration_ns': str(duration),
        'component_tree': {'A': ['B'], 'B': ['A']}
    }
    with open(f'/app/corpus/evil/evil_cycle_{i}.json', 'w') as f:
        json.dump(payload, f)

# Evil corpus - Precision loss
for i in range(10):
    start = 1600000000000000000 + i * 1000000
    duration = 5000000
    # Add a small integer that float comparison ignores
    end = start + duration + 1
    payload = {
        'start_ns': str(start),
        'end_ns': str(end),
        'duration_ns': str(duration),
        'component_tree': {'A': ['B'], 'B': ['C']}
    }
    with open(f'/app/corpus/evil/evil_precision_{i}.json', 'w') as f:
        json.dump(payload, f)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user

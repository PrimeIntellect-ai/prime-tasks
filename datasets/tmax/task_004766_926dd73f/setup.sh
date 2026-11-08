#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server
    pip3 install pytest flask redis python-dateutil

    mkdir -p /app
    cat << 'EOF' > /app/oracle_time_parser.py
from dateutil import parser
from datetime import timezone

def parse_and_normalize(time_str):
    try:
        dt = parser.parse(time_str)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        dt_utc = dt.astimezone(timezone.utc)
        return dt_utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        raise ValueError("Invalid time format")
EOF
    python3 -c "import py_compile; py_compile.compile('/app/oracle_time_parser.py', cfile='/app/oracle_time_parser.pyc')"
    rm /app/oracle_time_parser.py

    mkdir -p /home/user/pipeline/nginx
    mkdir -p /home/user/pipeline/flask

    cat << 'EOF' > /home/user/pipeline/nginx/nginx.conf
worker_processes 1;
daemon off;
events { worker_connections 1024; }
http {
    server {
        listen 8080;
        location /api/ingest {
            proxy_pass http://127.0.0.1:5000/wrong_path;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/pipeline/flask/app.py
from flask import Flask, request, jsonify
import redis
import time_parser

app = Flask(__name__)
# Broken redis config
r = redis.Redis(host='127.0.0.1', port=6380, db=0)

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.json
    if not data or 'time' not in data:
        return jsonify({"error": "Missing time"}), 400
    try:
        normalized = time_parser.parse_and_normalize(data['time'])
        r.set(normalized, "ingested")
        return jsonify({"status": "success", "time": normalized}), 200
    except ValueError:
        return jsonify({"error": "Invalid time format"}), 400

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /home/user/pipeline/flask/time_parser.py
from dateutil import parser
from datetime import timezone

cache = {}

def parse_and_normalize(time_str):
    if time_str in cache:
        return cache[time_str]
    try:
        dt = parser.parse(time_str)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        dt_utc = dt.astimezone(timezone.utc)
        res = dt_utc.strftime("%Y-%m-%dT%H:%M:%SZ")
        cache[time_str] = res
        return res
    except Exception:
        raise ValueError("Invalid time format")
EOF

    cat << 'EOF' > /home/user/pipeline/start.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /home/user/pipeline/nginx/nginx.conf &
python3 /home/user/pipeline/flask/app.py &
wait
EOF
    chmod +x /home/user/pipeline/start.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /var/log/nginx /var/lib/nginx /run || true

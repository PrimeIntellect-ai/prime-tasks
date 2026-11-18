#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server
    pip3 install pytest flask scipy pandas redis python-dotenv

    mkdir -p /app/tests/corpus/clean /app/tests/corpus/evil /app/data_app /app/nginx

    cat << 'EOF' > /app/reference_baselines.csv
sensor_id,baseline_mean
S1,10.5
S2,45.0
S3,-2.1
EOF

    cat << 'EOF' > /app/tests/corpus/clean/clean1.json
[
    {"sensor_id": "S1", "timestamp": 1620000000, "value": 10.5},
    {"sensor_id": "S1", "timestamp": 1620000001, "value": 10.6},
    {"sensor_id": "S1", "timestamp": 1620000002, "value": 10.4}
]
EOF

    cat << 'EOF' > /app/tests/corpus/evil/evil1.json
[
    {"sensor_id": "S1", "timestamp": 1620000000, "value": 100.5},
    {"sensor_id": "S1", "timestamp": 1620000001, "value": 100.6},
    {"sensor_id": "S1", "timestamp": 1620000002, "value": 100.4}
]
EOF

    cat << 'EOF' > /app/data_app/app.py
import os
import tempfile
import subprocess
import json
from flask import Flask, request, jsonify
from dotenv import load_dotenv
import redis

load_dotenv()

app = Flask(__name__)

REDIS_HOST = os.environ.get("REDIS_HOST")
REDIS_PORT = os.environ.get("REDIS_PORT")
FILTER_SCRIPT = os.environ.get("FILTER_SCRIPT")

@app.route('/upload', methods=['POST'])
def upload():
    data = request.json
    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.json') as f:
        json.dump(data, f)
        temp_path = f.name

    try:
        result = subprocess.run(['python3', FILTER_SCRIPT, temp_path], capture_output=True, text=True)
        if result.returncode == 0 and result.stdout.strip() == "CLEAN":
            if REDIS_HOST and REDIS_PORT:
                r = redis.Redis(host=REDIS_HOST, port=int(REDIS_PORT))
                r.set("last_upload", json.dumps(data))
            return jsonify({"status": "CLEAN"}), 200
        else:
            return jsonify({"status": "EVIL"}), 400
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/data_app/.env
REDIS_HOST=
REDIS_PORT=
FILTER_SCRIPT=
EOF

    cat << 'EOF' > /app/nginx/nginx.conf
worker_processes 1;
events { worker_connections 1024; }
http {
    server {
        listen 8080;
        # Add proxy_pass here
    }
}
EOF

    cat << 'EOF' > /app/start.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/nginx/nginx.conf
cd /app/data_app && python3 app.py &
EOF
    chmod +x /app/start.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

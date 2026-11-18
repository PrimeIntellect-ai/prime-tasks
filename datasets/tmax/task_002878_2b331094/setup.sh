#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nginx redis-server curl
    pip3 install pytest flask redis

    mkdir -p /app
    cat << 'EOF' > /app/api.py
import subprocess
import redis
from flask import Flask, request, jsonify

app = Flask(__name__)
r = redis.Redis(host='127.0.0.1', port=6379, decode_responses=True)

@app.route('/ingest', methods=['POST'])
def ingest():
    payload = request.get_data()
    try:
        result = subprocess.run(['/home/user/normalizer'], input=payload, capture_output=True, timeout=5)
        if result.returncode != 0:
            return jsonify({"error": result.stdout.decode('utf-8', errors='replace')}), 400

        normalized = result.stdout.decode('utf-8')
        r.rpush('configs', normalized)
        return jsonify({"status": "ok"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl nodejs
    pip3 install pytest flask

    mkdir -p /home/user/api /home/user/tests

    cat << 'EOF' > /home/user/api/server.py
import time
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/process', methods=['POST'])
def process_data():
    # Currently lacks validation and rate limiting
    data = request.get_json(silent=True) or {}
    return jsonify({"status": "processed", "processed_at": time.time()}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest flask redis numpy

    mkdir -p /home/user/services/config_api
    mkdir -p /home/user/services/receiver
    mkdir -p /var/opt

    cat << 'EOF' > /home/user/services/config_api/app.py
from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route('/stream')
def stream():
    return jsonify([])

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /home/user/services/config_api/settings.env
REDIS_URL=redis://127.0.0.1:9999
EOF

    cat << 'EOF' > /home/user/services/receiver/app.py
from flask import Flask, request
import json

app = Flask(__name__)

@app.route('/changelog', methods=['POST'])
def changelog():
    data = request.json
    with open('/tmp/reports.json', 'a') as f:
        f.write(json.dumps(data) + "\n")
    return "ok"

if __name__ == '__main__':
    app.run(port=5001)
EOF

    cat << 'EOF' > /var/opt/ground_truth.jsonl
{"event_id": "1", "server_id": "srv1", "timestamp": 1600000000.0, "cpu_limit": 2.0, "mem_limit": 1024, "config_blob": "configA"}
{"event_id": "2", "server_id": "srv1", "timestamp": 1600000010.0, "cpu_limit": 2.5, "mem_limit": 2048, "config_blob": "configB"}
EOF

    cat << 'EOF' > /var/opt/verify_imputation.py
import json
import sys

def verify():
    pass

if __name__ == "__main__":
    verify()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /var/opt

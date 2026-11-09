#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest flask redis

    mkdir -p /app/data/incoming
    mkdir -p /app/data/archive
    mkdir -p /app/api

    cat << 'EOF' > /app/data/incoming/file1.json
{"id": 1, "email": "admin@secret.com", "notes": "CONFIDENTIAL"}
EOF

    cat << 'EOF' > /app/data/incoming/file2.csv
2,bob@secret.com,CONFIDENTIAL data here
EOF

    cat << 'EOF' > /app/data/incoming/file3.json
{"id": 3, "email": "public@open.com", "notes": "Public info"}
EOF

    cat << 'EOF' > /app/api/app.py
from flask import Flask, jsonify
import redis

app = Flask(__name__)

# TODO: Connect to Redis and implement /manifest endpoint

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

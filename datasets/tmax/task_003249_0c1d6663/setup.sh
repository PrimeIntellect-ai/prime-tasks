#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        imagemagick \
        fonts-dejavu-core \
        tesseract-ocr \
        e2fsprogs \
        e2tools

    pip3 install pytest flask requests

    mkdir -p /app

    cat << 'EOF' > /app/server.py
from flask import Flask, request, jsonify
import os

app = Flask(__name__)
stored_logs = []

API_KEY = os.environ.get("API_KEY", "super-secret-token-99") # Fallback to default if not provided

@app.before_request
def check_auth():
    if request.headers.get("X-API-KEY") != API_KEY:
        return jsonify({"error": "Unauthorized"}), 401

@app.route('/logs', methods=['POST'])
def receive_logs():
    data = request.json
    if not data or not isinstance(data, list):
        return jsonify({"error": "Invalid format"}), 400

    processed_count = 0
    # BUG: Off-by-one error drops the last log entry
    for i in range(len(data) - 1):
        stored_logs.append(data[i])
        processed_count += 1

    return jsonify({"processed": processed_count}), 200

@app.route('/logs', methods=['GET'])
def get_logs():
    return jsonify({"logs": stored_logs}), 200

if __name__ == '__main__':
    port = int(os.environ.get("PORT", 8443))
    app.run(host='127.0.0.1', port=port)
EOF

    # Create ext4 volume and simulate file deletion
    dd if=/dev/zero of=/app/volume.img bs=1M count=10
    mkfs.ext4 -F /app/volume.img
    e2cp /app/server.py /app/volume.img:/server.py
    e2rm /app/volume.img:/server.py
    rm /app/server.py

    # Generate the dashboard image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
        -draw "text 10,30 'LOG AGGREGATOR DASHBOARD' text 10,60 'STATUS: ONLINE' text 10,90 'PORT: 8443' text 10,120 'X-API-KEY: super-secret-token-99'" \
        /app/dashboard.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user

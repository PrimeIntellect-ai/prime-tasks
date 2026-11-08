#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl xz-utils zstd tar redis-tools docker.io docker-compose
    pip3 install pytest flask redis

    mkdir -p /app
    cat << 'EOF' > /app/docker-compose.yml
version: '3'
services:
  redis:
    image: redis:alpine
    ports:
      - "6379:6379"
  log_api:
    build: .
    ports:
      - "5000:5000"
    volumes:
      - /home/user/raw_logs:/home/user/raw_logs
EOF

    cat << 'EOF' > /app/Dockerfile
FROM python:3.9-slim
RUN pip install flask
COPY app.py /app.py
CMD ["python", "/app.py"]
EOF

    cat << 'EOF' > /app/app.py
from flask import Flask
import os
import json
from datetime import datetime

app = Flask(__name__)

@app.route('/generate', methods=['POST'])
def generate():
    base_dir = '/home/user/raw_logs'
    os.makedirs(base_dir, exist_ok=True)
    # Generate highly repetitive logs to ensure high compression ratio
    for i in range(20):
        dir_path = os.path.join(base_dir, f'dir_{i}')
        os.makedirs(dir_path, exist_ok=True)
        for j in range(25):
            file_path = os.path.join(dir_path, f'log_{j}.log')
            with open(file_path, 'w') as f:
                for k in range(1000):
                    log_entry = {
                        "timestamp": "2023-10-01T12:00:00Z",
                        "level": "ERROR",
                        "message": "Connection timeout " * 20,
                        "service": "billing_service",
                        "trace_id": "1234567890abcdef" * 5
                    }
                    f.write(json.dumps(log_entry) + '\n')
    return "OK", 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/raw_logs /home/user/archives
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl docker.io docker-compose
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/gateway
    mkdir -p /home/user/app/processor

    cat << 'EOF' > /home/user/app/docker-compose.yml
version: '3.8'
services:
  gateway:
    build: ./gateway
    ports:
      - "127.0.0.1:8080:80"
    networks:
      - front-tier

  processor:
    build: ./processor
    networks:
      - back-tier

networks:
  front-tier:
  back-tier:
EOF

    cat << 'EOF' > /home/user/app/gateway/nginx.conf
server {
    listen 80;
    location /process {
        proxy_pass http://processor:5000/process;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

    cat << 'EOF' > /home/user/app/gateway/Dockerfile
FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
EOF

    cat << 'EOF' > /home/user/app/processor/app.py
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/process', methods=['POST'])
def process():
    data = request.json.get('data', '')
    return jsonify({"status": "ok", "result": f"{data.upper()}_ACK"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /home/user/app/processor/requirements.txt
Flask
Werkzeug
EOF

    cat << 'EOF' > /home/user/app/processor/Dockerfile
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY app.py .
CMD ["python", "app.py"]
EOF

    chown -R user:user /home/user/app
    chmod -R 777 /home/user

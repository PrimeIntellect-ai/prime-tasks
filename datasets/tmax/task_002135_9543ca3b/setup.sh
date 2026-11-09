#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core nginx curl
    pip3 install pytest flask gunicorn

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/app
    mkdir -p /home/user/nginx

    # Generate the image with the hidden ground truth
    convert -size 800x300 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -annotate +20+50 "Staging Setup Note:\nAPI_SECRET=X89F-SYS-BETA\nSOCK_PATH=/home/user/backend/sockets/api.sock" \
        /app/system_layout.png

    # Create Nginx config
    cat << 'EOF' > /home/user/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /api/ {
            proxy_pass http://127.0.0.1:9000;
        }
    }
}
EOF

    # Create Backend script
    cat << 'EOF' > /home/user/app/backend.py
from flask import Flask, request, jsonify
import os

app = Flask(__name__)
secret = os.environ.get('API_SECRET')

@app.route('/api/status')
def status():
    auth = request.headers.get('Authorization')
    if auth != f"Bearer {secret}":
        return jsonify({"error": "Forbidden"}), 403
    return jsonify({"status": "operational"}), 200

if __name__ == '__main__':
    app.run()
EOF

    # Create requirements.txt
    cat << 'EOF' > /home/user/app/requirements.txt
flask
gunicorn
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /var/log/nginx /var/lib/nginx /run || true

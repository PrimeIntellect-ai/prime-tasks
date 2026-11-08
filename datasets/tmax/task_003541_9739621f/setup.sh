#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        expect \
        nginx \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest flask gunicorn

    # Create directories
    mkdir -p /app/backend /app/nginx/logs /app/run /app/backup

    # Create the config snapshot image
    convert -size 800x300 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
      -draw "text 20,40 'SYSTEM PROVISIONING SHEET'" \
      -draw "text 20,80 '========================='" \
      -draw "text 20,120 'Backend Socket: /app/run/app_backend.sock'" \
      -draw "text 20,160 'Init PIN: 8492'" \
      /app/config_snapshot.png

    # Create the dummy backend initialization script
    cat << 'EOF' > /app/backend/init.sh
#!/bin/bash
read -p "Enter PIN: " pin
if [ "$pin" == "8492" ]; then
    echo "PIN verified. Writing token..."
    echo "AUTH_OK" > /app/backend/.auth_token
else
    echo "Invalid PIN."
    exit 1
fi
EOF
    chmod +x /app/backend/init.sh

    # Create the dummy backend server
    cat << 'EOF' > /app/backend/server.py
import argparse
import os
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--socket', required=True)
args = parser.parse_args()

flask_app = """
from flask import Flask
import os

app = Flask(__name__)

@app.route('/status')
def status():
    auth_token = "MISSING"
    if os.path.exists("/app/backend/.auth_token"):
        with open("/app/backend/.auth_token", "r") as f:
            auth_token = f.read().strip()
    return f"AUTH_OK" if auth_token == "AUTH_OK" else "FAIL"
"""
with open("/app/backend/app.py", "w") as f:
    f.write(flask_app)

print(f"Starting gunicorn on unix:{args.socket}")
subprocess.run(["gunicorn", "--bind", f"unix:{args.socket}", "app:app"], cwd="/app/backend")
EOF

    # Create the broken Nginx config
    cat << 'EOF' > /app/nginx/nginx.conf
worker_processes 1;
daemon off;
error_log /app/nginx/logs/error.log;
pid /app/nginx/nginx.pid;

events {
    worker_connections 1024;
}

http {
    access_log /app/nginx/logs/access.log;
    client_body_temp_path /app/nginx/client_body;
    proxy_temp_path /app/nginx/proxy_temp;
    fastcgi_temp_path /app/nginx/fastcgi_temp;
    uwsgi_temp_path /app/nginx/uwsgi_temp;
    scgi_temp_path /app/nginx/scgi_temp;

    server {
        listen 8080;
        server_name localhost;

        location / {
            proxy_pass http://unix:/app/run/wrong.sock;
            proxy_set_header Host $host;
        }
    }
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user

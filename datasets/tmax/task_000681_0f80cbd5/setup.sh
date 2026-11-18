#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx curl
pip3 install pytest

# Create directories
mkdir -p /home/user/nginx/client_body \
         /home/user/nginx/proxy \
         /home/user/nginx/fastcgi \
         /home/user/nginx/uwsgi \
         /home/user/nginx/scgi
mkdir -p /home/user/app
mkdir -p /home/user/source_data

# Create source data secret
echo "production_secret_data_7741" > /home/user/source_data/secret.txt

# Create dummy fstab
cat << 'EOF' > /home/user/fstab_config
# dummy fstab for user-level app mounting
/home/user/source_data /home/user/app/data none bind 0 0
EOF

# Create Nginx config with 502 Bug (proxy_pass points to 9000 instead of 8000)
cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
error_log /home/user/nginx/error.log;
events { worker_connections 1024; }
http {
    access_log /home/user/nginx/access.log;
    client_body_temp_path /home/user/nginx/client_body;
    proxy_temp_path /home/user/nginx/proxy;
    fastcgi_temp_path /home/user/nginx/fastcgi;
    uwsgi_temp_path /home/user/nginx/uwsgi;
    scgi_temp_path /home/user/nginx/scgi;

    server {
        listen 8080;
        server_name localhost;
        location / {
            proxy_pass http://127.0.0.1:9000;
        }
    }
}
EOF

# Create Python app requirements
cat << 'EOF' > /home/user/app/requirements.txt
flask==3.0.0
gunicorn==21.2.0
EOF

# Create Python app main.py
cat << 'EOF' > /home/user/app/main.py
from flask import Flask
import os

app = Flask(__name__)

@app.route('/')
def index():
    return "App is running"

@app.route('/data')
def data():
    data_path = '/home/user/app/data/secret.txt'
    if os.path.exists(data_path):
        with open(data_path, 'r') as f:
            return f.read().strip()
    return "Data not found", 404
EOF

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

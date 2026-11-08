#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git nginx supervisor curl
    pip3 install pytest flask gunicorn

    useradd -m -s /bin/bash user || true

    # Initialize directories
    mkdir -p /home/user/nginx/logs
    mkdir -p /home/user/nginx/client_body_temp
    mkdir -p /home/user/nginx/proxy_temp
    mkdir -p /home/user/nginx/fastcgi_temp
    mkdir -p /home/user/nginx/uwsgi_temp
    mkdir -p /home/user/nginx/scgi_temp
    mkdir -p /home/user/supervisor/logs
    mkdir -p /home/user/run
    mkdir -p /home/user/app
    mkdir -p /home/user/app_data/releases/initial
    mkdir -p /home/user/workspace

    # Set up dummy initial data
    echo '{"status": "uninitialized", "total": 0.0}' > /home/user/app_data/releases/initial/cost.json
    ln -sfn /home/user/app_data/releases/initial /home/user/app_data/current

    # Create Python Flask app
    cat << 'EOF' > /home/user/app/app.py
from flask import Flask, jsonify
import json
import os

app = Flask(__name__)

@app.route('/api/costs')
def get_costs():
    data_path = '/home/user/app_data/current/cost.json'
    if not os.path.exists(data_path):
        return jsonify({"error": "Data not found"}), 404
    with open(data_path, 'r') as f:
        data = json.load(f)
    return jsonify(data)

if __name__ == '__main__':
    app.run()
EOF

    # Nginx config (expects socket)
    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
error_log /home/user/nginx/logs/error.log;
pid /home/user/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /home/user/nginx/client_body_temp;
    proxy_temp_path /home/user/nginx/proxy_temp;
    fastcgi_temp_path /home/user/nginx/fastcgi_temp;
    uwsgi_temp_path /home/user/nginx/uwsgi_temp;
    scgi_temp_path /home/user/nginx/scgi_temp;

    server {
        listen 8080;
        server_name localhost;

        location / {
            proxy_pass http://unix:/home/user/run/app.sock;
            proxy_set_header Host $host;
        }
    }
}
EOF

    # Supervisor config (Binding to wrong address 127.0.0.1:8000 instead of socket)
    cat << 'EOF' > /home/user/supervisor/supervisord.conf
[unix_http_server]
file=/home/user/run/supervisor.sock

[supervisord]
logfile=/home/user/supervisor/logs/supervisord.log
pidfile=/home/user/run/supervisord.pid

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///home/user/run/supervisor.sock

[program:finops_app]
command=gunicorn --bind 127.0.0.1:8000 app:app
directory=/home/user/app
autostart=true
autorestart=true
EOF

    # Setup bare git repo
    git init --bare /home/user/cost-data.git

    # Set permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user

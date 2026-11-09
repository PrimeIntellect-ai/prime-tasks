#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx supervisor curl
    pip3 install pytest flask

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs \
             /home/user/supervisor \
             /home/user/nginx \
             /home/user/app_data \
             /home/user/nginx/client_body \
             /home/user/nginx/proxy \
             /home/user/nginx/fastcgi \
             /home/user/nginx/uwsgi \
             /home/user/nginx/scgi

    # Create the bloated file
    dd if=/dev/zero of=/home/user/app_data/junk.log bs=1M count=10

    # Create api-service.py
    cat << 'EOF' > /home/user/api-service.py
import os
import sys
from flask import Flask

def get_dir_size(path):
    total = 0
    for dirpath, _, filenames in os.walk(path):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            if not os.path.islink(fp):
                total += os.path.getsize(fp)
    return total

if get_dir_size('/home/user/app_data') > 5 * 1024 * 1024:
    print("FATAL: Storage quota exceeded")
    sys.exit(1)

app = Flask(__name__)

@app.route('/ping')
def ping():
    return "pong"

@app.route('/data', methods=['POST'])
def data():
    return "ok"

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create nginx.conf
    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
daemon off;
error_log /home/user/logs/nginx_error.log;
pid /home/user/nginx/nginx.pid;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/logs/nginx_access.log;
    client_body_temp_path /home/user/nginx/client_body;
    proxy_temp_path /home/user/nginx/proxy;
    fastcgi_temp_path /home/user/nginx/fastcgi;
    uwsgi_temp_path /home/user/nginx/uwsgi;
    scgi_temp_path /home/user/nginx/scgi;

    server {
        listen 8080;
        server_name localhost;

        location / {
            proxy_pass http://127.0.0.1:5001;
        }
    }
}
EOF

    # Create supervisord.conf
    cat << 'EOF' > /home/user/supervisor/supervisord.conf
[supervisord]
nodaemon=true
logfile=/home/user/logs/supervisord.log
pidfile=/home/user/supervisor/supervisord.pid

[unix_http_server]
file=/home/user/supervisor/supervisor.sock

[supervisorctl]
serverurl=unix:///home/user/supervisor/supervisor.sock

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[program:api-service]
command=python3 /home/user/api-service.py
autostart=true
autorestart=false
stdout_logfile=/home/user/logs/api-service.log
stderr_logfile=/home/user/logs/api-service.err

[program:nginx]
command=nginx -c /home/user/nginx/nginx.conf
autostart=true
autorestart=true
stdout_logfile=/home/user/logs/nginx.log
stderr_logfile=/home/user/logs/nginx.err

[program:storage-monitor]
command=/home/user/storage-monitor.sh
autostart=true
autorestart=true
stdout_logfile=/home/user/logs/storage-monitor.log
stderr_logfile=/home/user/logs/storage-monitor.err
EOF

    # Create storage-monitor.sh
    cat << 'EOF' > /home/user/storage-monitor.sh
#!/bin/bash
while true; do
  sleep 60
done
EOF
    chmod +x /home/user/storage-monitor.sh

    chown -R user:user /home/user
    chmod -R 777 /home/user

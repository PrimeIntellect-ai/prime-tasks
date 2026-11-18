#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx supervisor curl procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/nginx/logs /home/user/nginx/temp /home/user/supervisor/logs /home/user/app /home/user/run

    # Create python app
    cat << 'EOF' > /home/user/app/server.py
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

if os.environ.get('API_SECRET') != 'staging_secret_99':
    sys.exit(1)

class SimpleHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status": "ok"}')
        else:
            self.send_response(404)
            self.end_headers()

server = HTTPServer(('127.0.0.1', 9001), SimpleHandler)
server.serve_forever()
EOF

    # Create nginx.conf
    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
pid /home/user/nginx/nginx.pid;
events {
    worker_connections 1024;
}
http {
    client_body_temp_path /home/user/nginx/temp/client_body;
    proxy_temp_path /home/user/nginx/temp/proxy;
    fastcgi_temp_path /home/user/nginx/temp/fastcgi;
    uwsgi_temp_path /home/user/nginx/temp/uwsgi;
    scgi_temp_path /home/user/nginx/temp/scgi;

    access_log /home/user/nginx/logs/access.log;
    error_log /home/user/nginx/logs/error.log;

    server {
        listen 8080;
        server_name localhost;

        location /api/ {
            proxy_pass http://127.0.0.1:9000/;
        }
    }
}
EOF

    # Create supervisord.conf
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

[program:backend-api]
command=python3 /home/user/app/server.py
autostart=true
autorestart=true
stderr_logfile=/home/user/supervisor/logs/api.err.log
stdout_logfile=/home/user/supervisor/logs/api.out.log
EOF

    # Create deploy.sh
    cat << 'EOF' > /home/user/deploy.sh
#!/bin/bash
echo "Deploying latest application code..."
# TODO: Restart the application via supervisorctl
EOF
    chmod +x /home/user/deploy.sh

    chmod -R 777 /home/user

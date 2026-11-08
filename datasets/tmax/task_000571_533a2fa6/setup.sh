#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect nginx curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/nginx/logs /home/user/nginx/temp /home/user/backend

    cat << 'EOF' > /home/user/backend/app.py
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Hello from Production backend!")

if __name__ == "__main__":
    # App purposefully runs on 9001 instead of 9000
    server = HTTPServer(("127.0.0.1", 9001), Handler)
    server.serve_forever()
EOF

    cat << 'EOF' > /home/user/deploy.sh
#!/bin/bash
read -p "Environment (dev/prod): " env
read -p "Confirm start? [y/N]: " conf

if [ "$env" == "prod" ] && [ "$conf" == "y" ]; then
    echo "Starting backend..."
    python3 /home/user/backend/app.py &
    echo $! > /home/user/backend/app.pid
    sleep 1
    echo "Backend started."
else
    echo "Deployment aborted."
    exit 1
fi
EOF
    chmod +x /home/user/deploy.sh

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
error_log /home/user/nginx/logs/error.log;
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

    server {
        listen 8080;
        server_name localhost;

        location / {
            # Flaw: Backend runs on 9001, but this points to 9000
            proxy_pass http://127.0.0.1:9000;
        }
    }
}
EOF

    chmod -R 777 /home/user

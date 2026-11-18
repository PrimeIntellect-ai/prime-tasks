#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server gcc curl
    pip3 install pytest

    mkdir -p /app/secure_data /app/config /app/corpus/clean /app/corpus/evil

    # Secure data files
    touch /app/secure_data/server.crt /app/secure_data/server.key
    chmod 777 /app/secure_data/server.crt
    chmod 666 /app/secure_data/server.key

    # Config files
    cat << 'EOF' > /app/config/nginx.conf
events {}
http {
    server {
        listen 8080;
        # TODO: Proxy pass to backend
    }
}
EOF

    cat << 'EOF' > /app/config/backend.env
REDIS_HOST=placeholder
REDIS_PORT=0
EOF

    # Fake backend
    cat << 'EOF' > /app/backend
#!/usr/bin/env python3
import os
from http.server import HTTPServer, BaseHTTPRequestHandler

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/health':
            host = os.environ.get('REDIS_HOST')
            port = os.environ.get('REDIS_PORT')
            if host == '127.0.0.1' and port == '6379':
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"status": "ok"}')
            else:
                self.send_response(500)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 9000), Handler)
    server.serve_forever()
EOF
    chmod +x /app/backend

    # Start services script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
cp /app/config/nginx.conf /etc/nginx/nginx.conf
service nginx start
service redis-server start
source /app/config/backend.env
export REDIS_HOST REDIS_PORT
nohup /app/backend > /dev/null 2>&1 &
EOF
    chmod +x /app/start_services.sh

    # Corpora
    echo "192.168.1.1 GET /index.html" > /app/corpus/clean/log1.txt
    echo "10.0.0.1 GET /login ' OR '1'='1" > /app/corpus/evil/test_log_1.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

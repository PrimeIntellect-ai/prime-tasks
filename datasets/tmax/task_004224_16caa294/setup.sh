#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest requests

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/billing_datastore.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/internal/metrics':
            auth_header = self.headers.get('Authorization')
            if auth_header == 'Bearer opt-cost-2024':
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"cloud_cost": 420.50}).encode())
            else:
                self.send_response(403)
                self.end_headers()
                self.wfile.write(b"Forbidden")
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 9092), RequestHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > /home/user/app/cost_analyzer.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
import urllib.request

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/v1/costs':
            host = os.environ.get('DATASTORE_HOST', '127.0.0.1')
            port = os.environ.get('DATASTORE_PORT', '9092')
            api_key = os.environ.get('FINOPS_API_KEY', '')

            req = urllib.request.Request(f"http://{host}:{port}/internal/metrics")
            req.add_header('Authorization', f"Bearer {api_key}")

            try:
                with urllib.request.urlopen(req) as response:
                    data = json.loads(response.read().decode())
                    self.send_response(200)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps({"status": "optimized", "data": data}).encode())
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(e).encode())
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 9091), RequestHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > /home/user/app/nginx.conf
worker_processes 1;
error_log /var/log/nginx/error.log;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    server {
        listen 80;
        server_name localhost;

        location / {
            root /var/www/html;
            index index.html;
        }
    }
}
EOF

    chmod -R 777 /home/user

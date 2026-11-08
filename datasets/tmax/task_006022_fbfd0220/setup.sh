#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip haproxy supervisor
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/supervisor /home/user/haproxy
    cat << 'EOF' > /home/user/uptime_api.py
#!/usr/bin/env python3
import http.server
import json

class HealthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "UP", "uptime": 9999}).encode())
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = http.server.HTTPServer(('127.0.0.1', 9000), HealthHandler)
    server.serve_forever()
EOF
    chmod +x /home/user/uptime_api.py

    chmod -R 777 /home/user

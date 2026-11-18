#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/api.py
import http.server
import socketserver
import json

class APIHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        response = {"status": "ok", "metric": 42, "source": "api"}
        self.wfile.write(json.dumps(response).encode())

with socketserver.TCPServer(("127.0.0.1", 8081), APIHandler) as httpd:
    httpd.serve_forever()
EOF

    cat << 'EOF' > /home/user/dashboard.py
import http.server
import socketserver
import urllib.request
import json

class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        try:
            req = urllib.request.Request("http://127.0.0.1:9090/")
            with urllib.request.urlopen(req, timeout=2) as response:
                data = json.loads(response.read().decode())
            res = {"dashboard": "up", "data": data}
            status = 200
        except Exception as e:
            res = {"dashboard": "down", "error": str(e)}
            status = 502

        self.send_response(status)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(res).encode())

with socketserver.TCPServer(("127.0.0.1", 8082), DashboardHandler) as httpd:
    httpd.serve_forever()
EOF

    chmod -R 777 /home/user

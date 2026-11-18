#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron procps
    pip3 install pytest

    mkdir -p /app/vendor/metrics_server-1.0.0
    cat << 'EOF' > /app/vendor/metrics_server-1.0.0/server.py
import os
import json
import http.server
import socketserver

PORT = 80 # PERTURBATION: hardcoded to 80

class MetricsHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        try:
            with open("/home/user/stats.json", "r") as f:
                data = f.read()
            self.wfile.write(data.encode())
        except Exception as e:
            self.wfile.write(json.dumps({"error": str(e)}).encode())

with socketserver.TCPServer(("", int(PORT)), MetricsHandler) as httpd:
    httpd.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /app/vendor/metrics_server-1.0.0
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest

    mkdir -p /home/user/microservices

    cat << 'EOF' > /home/user/microservices/config.json
{
  "api_ports": [8081, 8082],
  "email_port": 9025,
  "proxy_port": 8080
}
EOF

    cat << 'EOF' > /home/user/microservices/start_services.py
import json
import http.server
import socketserver
import threading
import time

with open('/home/user/microservices/config.json', 'r') as f:
    config = json.load(f)

class APIServer1(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"API_RESPONSE_8081")

class APIServer2(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"API_RESPONSE_8082")

class EmailServer(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"EMAIL_SERVICE_ACK")

def run_server(handler, port):
    with socketserver.TCPServer(("", port), handler) as httpd:
        httpd.serve_forever()

threading.Thread(target=run_server, args=(APIServer1, config["api_ports"][0]), daemon=True).start()
threading.Thread(target=run_server, args=(APIServer2, config["api_ports"][1]), daemon=True).start()
# Email server always uses 8025 internally for its binding in this simulation
threading.Thread(target=run_server, args=(EmailServer, 8025), daemon=True).start()

while True:
    time.sleep(1)
EOF

    chmod +x /home/user/microservices/start_services.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

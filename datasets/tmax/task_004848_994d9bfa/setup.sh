#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip logrotate curl netcat-openbsd
pip3 install pytest

mkdir -p /app/edge-telemetry

cat << 'EOF' > /app/edge-telemetry/server.py
import argparse
import threading
import socket
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--host', required=True)
parser.add_argument('--http', type=int, required=True)
parser.add_argument('--tcp', type=int, required=True)
args = parser.parse_args()

if not args.host:
    print("Error: --host cannot be empty")
    sys.exit(1)

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "healthy"}).encode())
        else:
            self.send_response(404)
            self.end_headers()

def run_http():
    try:
        server = HTTPServer((args.host, args.http), HealthHandler)
        server.serve_forever()
    except Exception as e:
        print(f"HTTP Server error: {e}")

def run_tcp():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((args.host, args.tcp))
        s.listen()
        while True:
            conn, addr = s.accept()
            data = conn.recv(1024)
            if b'PING' in data:
                conn.sendall(b'PONG\n')
            conn.close()
    except Exception as e:
        print(f"TCP Server error: {e}")

t1 = threading.Thread(target=run_http, daemon=True)
t2 = threading.Thread(target=run_tcp, daemon=True)
t1.start()
t2.start()

t1.join()
t2.join()
EOF

cat << 'EOF' > /app/edge-telemetry/start.sh
#!/bin/bash
export HOSST="0.0.0.0"
nohup python3 /app/edge-telemetry/server.py --host $HOST --http 8080 --tcp 8081 >> /home/user/logs/telemetry.log 2>&1 &
EOF

chmod +x /app/edge-telemetry/start.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

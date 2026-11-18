#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/deploy

    cat << 'EOF' > /home/user/deploy/worker.py
import sys
import time
import socket
import os
from http.server import HTTPServer, BaseHTTPRequestHandler

def check_dep(prev_id, prev_port):
    # Check filesystem dependency
    if not os.path.exists(f"/home/user/deploy/w{prev_id}.ready"):
        print(f"Worker {prev_id} readiness file not found. Crashing.")
        sys.exit(1)
    # Check network dependency
    try:
        with socket.create_connection(("127.0.0.1", prev_port), timeout=1):
            pass
    except OSError:
        print(f"Worker {prev_id} port {prev_port} not reachable. Crashing.")
        sys.exit(1)

worker_id = int(sys.argv[1])
port = 8080 + worker_id

if worker_id > 1:
    check_dep(worker_id - 1, port - 1)

# Simulate startup delay
time.sleep(2)

# Start server
class DummyHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()

server = HTTPServer(('127.0.0.1', port), DummyHandler)

# Write readiness file
with open(f"/home/user/deploy/w{worker_id}.ready", "w") as f:
    f.write("ready")

# Serve forever
server.serve_forever()
EOF

    cat << 'EOF' > /home/user/deploy/deploy.py
import subprocess
import time

print("Starting all workers...")
subprocess.Popen(["python3", "/home/user/deploy/worker.py", "1"])
subprocess.Popen(["python3", "/home/user/deploy/worker.py", "2"])
subprocess.Popen(["python3", "/home/user/deploy/worker.py", "3"])

print("Deployment scripts launched.")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

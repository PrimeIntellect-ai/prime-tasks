#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git ffmpeg libsm6 libxext6 python3-opencv
    pip3 install pytest numpy opencv-python

    # Create directories
    mkdir -p /app
    mkdir -p /var/log
    mkdir -p /home/user/monitor_repo

    # Generate log files
    echo "2023-10-27T15:30:00Z Service A event" > /var/log/service_a.log
    echo "2023-10-27T11:30:00-04:00 Service B event" > /var/log/service_b.log

    # Generate video file
    cat << 'EOF' > /app/make_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/dashboard_feed.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (200, 200))
for i in range(300):
    frame = np.zeros((200, 200, 3), dtype=np.uint8)
    if i >= 142:
        frame[100:110, 100:110] = [0, 0, 255] # BGR for red
    out.write(frame)
out.release()
EOF
    python3 /app/make_video.py
    rm /app/make_video.py

    # Setup git repository
    cd /home/user/monitor_repo
    git init
    git config user.name "Admin"
    git config user.email "admin@example.com"

    # Commit 1
    cat << 'EOF' > server.py
import math
from datetime import datetime
def calculate_sla(time_str):
    dt = datetime.strptime(time_str, "%Y-%m-%dT%H:%M:%SZ")
    now = datetime.utcnow()
    delta = now - dt
    return math.sqrt(abs(delta.total_seconds()))
EOF
    git add server.py
    git commit -m "Baseline server implementation"

    # Commit 2
    cat << 'EOF' > server.py
import math
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

def calculate_sla(time_str):
    dt = datetime.strptime(time_str, "%Y-%m-%dT%H:%M:%SZ")
    now = datetime.utcnow()
    delta = now - dt
    return math.sqrt(abs(delta.total_seconds()))

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/api/v1/sla':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data)
            sla = calculate_sla(data['event_time'])
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "sla": sla}).encode())
EOF
    git add server.py
    git commit -m "Added /api/v1/sla endpoint"

    # Commit 3 (Bad)
    cat << 'EOF' > server.py
import math
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

def calculate_sla(time_str):
    dt = datetime.strptime(time_str, "%Y-%m-%dT%H:%M:%SZ")
    now = datetime.utcnow()
    delta = dt - now
    return math.sqrt(delta.total_seconds())

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/api/v1/sla':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data)
            sla = calculate_sla(data['event_time'])
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "sla": sla}).encode())
EOF
    git add server.py
    git commit -m "Introduced timezone bug"

    # Commit 4
    cat << 'EOF' > server.py
import math
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import logging

logging.basicConfig(level=logging.INFO)

def calculate_sla(time_str):
    logging.info(f"Calculating SLA for {time_str}")
    dt = datetime.strptime(time_str, "%Y-%m-%dT%H:%M:%SZ")
    now = datetime.utcnow()
    delta = dt - now
    return math.sqrt(delta.total_seconds())

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/api/v1/sla':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data)
            sla = calculate_sla(data['event_time'])
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "sla": sla}).encode())
EOF
    git add server.py
    git commit -m "Refactored logging"

    # Commit 5
    cat << 'EOF' > server.py
import math
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import logging

logging.basicConfig(level=logging.INFO)

def calculate_sla(time_str):
    logging.info(f"Calculating SLA for {time_str}")
    dt = datetime.strptime(time_str, "%Y-%m-%dT%H:%M:%SZ")
    now = datetime.utcnow()
    delta = dt - now
    return math.sqrt(delta.total_seconds())

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/api/v1/sla':
            auth = self.headers.get('Authorization')
            if auth != 'Bearer uptime-token-2024':
                self.send_response(401)
                self.end_headers()
                return
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data)
            sla = calculate_sla(data['event_time'])
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "sla": sla}).encode())

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), Handler)
    server.serve_forever()
EOF
    git add server.py
    git commit -m "Added auth token check"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /var/log

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv ffmpeg libgl1 libglib2.0-0
    pip3 install --default-timeout=100 pytest pillow opencv-python

    mkdir -p /app
    mkdir -p /home/user/messy_files

    cat << 'EOF' > /home/user/messy_files/auth_service.py
import sys, json
from http.server import BaseHTTPRequestHandler, HTTPServer
port = int(sys.argv[2]) if len(sys.argv) > 2 else 8001
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"service": "auth", "status": "ok"}).encode())
HTTPServer(('127.0.0.1', port), Handler).serve_forever()
EOF

    cat << 'EOF' > /home/user/messy_files/user_service.py
import sys, json
from http.server import BaseHTTPRequestHandler, HTTPServer
port = int(sys.argv[2]) if len(sys.argv) > 2 else 8002
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"service": "user", "status": "ok"}).encode())
HTTPServer(('127.0.0.1', port), Handler).serve_forever()
EOF

    cat << 'EOF' > /tmp/make_video.py
import cv2
import numpy as np
import json

config = '{"file_mapping": {"auth_service.py": "backends/auth_service.py", "user_service.py": "backends/user_service.py"}, "routes": {"/auth": 8001, "/users": 8002}}'

width, height = 64, 64
out = cv2.VideoWriter('/app/secret_architecture.avi', cv2.VideoWriter_fourcc(*'FFV1'), 10, (width, height))

for char in config:
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    frame[0, 0, 2] = ord(char) # OpenCV uses BGR, so Red is index 2
    out.write(frame)

# add padding frames
for _ in range(10):
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    out.write(frame)

out.release()
EOF
    python3 /tmp/make_video.py
    ffmpeg -i /app/secret_architecture.avi -c:v libx264rgb -crf 0 /app/secret_architecture.mp4 -y

    cat << 'EOF' > /home/user/verify.py
import urllib.request
import json
import sys

def check():
    correct = 0
    total = 2
    try:
        req = urllib.request.urlopen("http://127.0.0.1:8000/auth")
        data = json.loads(req.read().decode())
        if data.get("service") == "auth": correct += 1
    except Exception as e:
        pass

    try:
        req = urllib.request.urlopen("http://127.0.0.1:8000/users")
        data = json.loads(req.read().decode())
        if data.get("service") == "user": correct += 1
    except Exception as e:
        pass

    accuracy = correct / total
    print(f"accuracy={accuracy}")
    if accuracy < 1.0:
        sys.exit(1)

if __name__ == "__main__":
    check()
EOF
    chmod +x /home/user/verify.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

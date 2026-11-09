#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg git
    pip3 install pytest opencv-python-headless numpy

    # Create directories
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil
    mkdir -p /home/user/gateway

    # Generate incident.mp4
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/incident.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (100, 100))
green = np.zeros((100, 100, 3), dtype=np.uint8)
green[:] = (0, 255, 0) # BGR
red = np.zeros((100, 100, 3), dtype=np.uint8)
red[:] = (0, 0, 255) # BGR

for i in range(300):
    if 142 <= i <= 180:
        out.write(red)
    else:
        out.write(green)
out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    # Setup git repository
    cd /home/user/gateway
    git init
    git config user.email "admin@example.com"
    git config user.name "Admin"
    cat << 'EOF' > nginx.conf
server {
    listen 80;
    location / {
        proxy_pass http://127.0.0.1:8080;
    }
}
EOF
    git add nginx.conf
    git commit -m "Initial config"

    # Setup corpora
    cat << 'EOF' > /app/corpus/clean/req1.req
GET /index.html HTTP/1.1
Host: localhost
EOF

    cat << 'EOF' > /app/corpus/clean/req2.req
GET /images/logo.png HTTP/1.1
Host: localhost
EOF

    cat << 'EOF' > /app/corpus/evil/req1.req
GET /api/v1/../../etc/passwd HTTP/1.1
Host: localhost
EOF

    cat << 'EOF' > /app/corpus/evil/req2.req
GET /assets/%2e%2e/config HTTP/1.1
Host: localhost
EOF

    cat << 'EOF' > /app/corpus/evil/req3.req
GET /assets/%2E%2E/config HTTP/1.1
Host: localhost
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user

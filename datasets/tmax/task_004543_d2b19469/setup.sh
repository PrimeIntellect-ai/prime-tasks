#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip iproute2 net-tools lsof
    pip3 install pytest opencv-python-headless numpy requests

    mkdir -p /app

    # Create the video file
    cat << 'EOF' > /app/make_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/rack_monitor.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (64, 64))
truth_frames = {45, 120, 315, 800, 1024, 1500, 1750}

for i in range(1800):
    frame = np.zeros((64, 64, 3), dtype=np.uint8)
    if i in truth_frames:
        frame[:, :] = (0, 0, 255) # OpenCV uses BGR
    out.write(frame)
out.release()
EOF
    python3 /app/make_video.py

    # Create the HTTP server script
    cat << 'EOF' > /app/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
class MyHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        self.send_response(200)
        self.end_headers()
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
HTTPServer(('127.0.0.1', 8192), MyHandler).serve_forever()
EOF

    # Hook the server to start when the container runs
    cat << 'EOF' > /.singularity.d/env/99-server.sh
#!/bin/sh
if ! ss -tuln | grep -q ":8192"; then
    python3 /app/server.py >/dev/null 2>&1 &
    sleep 0.5
fi
EOF
    chmod +x /.singularity.d/env/99-server.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip supervisor ffmpeg openssl
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /home/user
    mkdir -p /app

    cat << 'EOF' > /home/user/supervisord.conf
[supervisord]
nodaemon=true
logfile=/home/user/supervisord.log

[program:cert-generator]
command=bash -c "openssl req -x509 -newkey rsa:4096 -keyout /home/user/key.pem -out /home/user/cert.pem -days 365 -nodes -subj '/CN=localhost' && sleep 1000"
autostart=true
autorestart=false

[program:dashboard-web]
command=python3 -c "import http.server, ssl; server = http.server.HTTPServer(('localhost', 8443), http.server.SimpleHTTPRequestHandler); server.socket = ssl.wrap_socket(server.socket, certfile='/home/user/cert.pem', keyfile='/home/user/key.pem', server_side=True); server.serve_forever()"
autostart=true
autorestart=true
EOF

    cat << 'EOF' > /app/oracle_analyze_link.py
import sys
import cv2
import numpy as np

def main():
    frame_idx = int(sys.argv[1])
    threshold = int(sys.argv[2])

    cap = cv2.VideoCapture('/app/switch_lights.mp4')
    cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
    ret, frame = cap.read()
    if not ret:
        print("LINK_DOWN")
        sys.exit(0)

    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    roi = gray[0:50, 0:50]
    avg_brightness = np.mean(roi)

    if avg_brightness > threshold:
        print("LINK_UP")
    else:
        print("LINK_DOWN")

if __name__ == "__main__":
    main()
EOF

    # Generate the video fixture
    cat << 'EOF' > /app/generate_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/switch_lights.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (640, 480))
for i in range(300):
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    if (i // 15) % 2 == 0:
        frame[0:50, 0:50] = 255
    out.write(frame)
out.release()
EOF
    python3 /app/generate_video.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user

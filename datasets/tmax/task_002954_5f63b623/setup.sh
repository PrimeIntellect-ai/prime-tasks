#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-opencv ffmpeg imagemagick bc gawk
    pip3 install pytest

    mkdir -p /app

    # Generate the video
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/traffic_monitor.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 1, (300, 300))

for i in range(60):
    frame = np.zeros((300, 300, 3), dtype=np.uint8)

    # Node 1 (Top 0-100)
    if i < 45:
        frame[0:100, :, :] = [0, 255, 0] # BGR for Green
    else:
        frame[0:100, :, :] = [0, 0, 255] # BGR for Red

    # Node 2 (Mid 100-200)
    if i < 30:
        frame[100:200, :, :] = [0, 255, 0]
    else:
        frame[100:200, :, :] = [0, 0, 255]

    # Node 3 (Bot 200-300)
    if i < 60:
        frame[200:300, :, :] = [0, 255, 0]
    else:
        frame[200:300, :, :] = [0, 0, 255]

    out.write(frame)

out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    # Create CSV file
    cat << 'EOF' > /app/team.csv
username,team_name
alice,backend
bob,frontend
charlie,backend
diana,devops
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

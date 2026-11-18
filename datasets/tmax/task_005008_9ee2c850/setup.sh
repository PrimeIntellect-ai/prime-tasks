#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libsm6 libxext6 libgl1
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app
    mkdir -p /home/user

    # Create versions.txt with 30 lines
    cat << 'EOF' > /home/user/versions.txt
auth-service 1.0.0
auth-service 1.1.0
auth-service 1.2.0
auth-service 1.2.1
auth-service 2.0.0
payment-api 0.1.0
payment-api 0.2.0
payment-api 0.2.1
payment-api 0.3.0
payment-api 1.0.0
EOF

    # Pad the remaining 20 lines with dummy red versions
    for i in $(seq 11 30); do
        echo "dummy-service $i.0.0" >> /home/user/versions.txt
    done

    # Generate the 30-frame video
    cat << 'EOF' > /tmp/gen_vid.py
import cv2
import numpy as np

# First 10 statuses based on ground truth, remaining 20 padded as red to keep total green count at 7
statuses = ['red', 'green', 'red', 'green', 'green', 'green', 'green', 'green', 'red', 'green']
statuses += ['red'] * 20

frames = []
for status in statuses:
    img = np.zeros((100, 100, 3), dtype=np.uint8)
    if status == 'red':
        img[0:10, 0:10] = [0, 0, 255] # BGR
    else:
        img[0:10, 0:10] = [0, 255, 0] # BGR
    frames.append(img)

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/deploy_logs.mp4', fourcc, 1.0, (100, 100))
for f in frames:
    out.write(f)
out.release()
EOF
    python3 /tmp/gen_vid.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

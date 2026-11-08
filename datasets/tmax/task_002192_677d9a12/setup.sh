#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libzbar0 ffmpeg libsm6 libxext6
    pip3 install pytest qrcode opencv-python numpy Pillow

    cat << 'EOF' > /tmp/generate_video.py
import os
import json
import qrcode
import cv2
import numpy as np

os.makedirs('/app', exist_ok=True)
video_path = '/app/cloud_telemetry.mp4'

services = [
    {"service": "api_gateway", "base_cost": 300.0, "idle_waste": 50.0},
    {"service": "auth_service", "base_cost": 150.0, "idle_waste": 20.0},
    {"service": "db_cluster", "base_cost": 600.0, "idle_waste": 150.0},
    {"service": "cache_layer", "base_cost": 100.0, "idle_waste": 15.0},
    {"service": "worker_nodes", "base_cost": 400.0, "idle_waste": 70.0}
]

fps = 2
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter(video_path, fourcc, fps, (400, 400))

for s in services:
    qr = qrcode.QRCode(version=1, box_size=10, border=4)
    qr.add_data(json.dumps(s))
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white").convert('RGB')
    frame = np.array(img)
    frame = cv2.resize(frame, (400, 400))
    for _ in range(5):
        out.write(frame)

out.release()
EOF

    python3 /tmp/generate_video.py
    rm /tmp/generate_video.py

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/logs
    chmod -R 777 /home/user
    chmod -R 777 /app

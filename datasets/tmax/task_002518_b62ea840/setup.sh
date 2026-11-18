#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install --no-cache-dir pytest opencv-python-headless numpy networkx flask jsonschema requests

    mkdir -p /app
    cat << 'EOF' > /app/generate_video.py
import cv2
import numpy as np
import os

os.makedirs('/app', exist_ok=True)
out = cv2.VideoWriter('/app/traffic_sensor.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (100, 100))
for i in range(600):
    if i in [45, 120, 315]:
        frame = np.full((100, 100, 3), 255, dtype=np.uint8)
    else:
        frame = np.zeros((100, 100, 3), dtype=np.uint8)
    out.write(frame)
out.release()
EOF
    python3 /app/generate_video.py

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/logistics_data

    cat << 'EOF' > /home/user/logistics_data/data_alpha_99.csv
id,type,name
n1,driver,Alice
n2,driver,Bob
n3,driver,Charlie
n4,vehicle,TruckA
n5,vehicle,TruckB
n6,ping,45
n7,ping,120
n8,ping,315
n9,ping,500
EOF

    cat << 'EOF' > /home/user/logistics_data/rel_beta_42.csv
source,target,relation
n1,n4,drove
n2,n5,drove
n3,n4,drove
n4,n6,detected_at
n4,n7,detected_at
n5,n9,detected_at
n4,n8,detected_at
EOF

    chmod -R 777 /home/user /app

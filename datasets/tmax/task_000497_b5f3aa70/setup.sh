#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app
    useradd -m -s /bin/bash user || true

    # Generate the video and JSON configurations
    python3 -c "
import cv2
import numpy as np
import json

# Generate Video
width, height = 400, 400
fps = 10
frames = 30 # 3 seconds video

out = cv2.VideoWriter('/app/dashboard_traffic.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (width, height))
affected = {2, 5, 11, 14}

for i in range(frames):
    img = np.zeros((height, width, 3), dtype=np.uint8)
    for r in range(4):
        for c in range(4):
            idx = r * 4 + c
            # BGR format
            if idx in affected and 10 <= i < 20:
                color = (0, 0, 255) # Red
            else:
                color = (0, 255, 0) # Green

            cv2.rectangle(img, (c*100, r*100), ((c+1)*100, (r+1)*100), color, -1)
    out.write(img)

out.release()

# Generate JSON
data = {}
for i in range(16):
    data[f'User{i:02d}'] = {'subnet': '10.0.0.0/24'}

with open('/home/user/network_configs.json', 'w') as f:
    json.dump(data, f, indent=4)
"

    chmod -R 777 /home/user
    chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang-go python3-opencv
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/server_cam.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (100, 100), isColor=False)

for sec in range(20):
    for frame in range(10):
        if sec in [5, 6]:
            # 5 flashes per sec
            if frame % 2 == 0:
                img = np.ones((100, 100), dtype=np.uint8) * 200
            else:
                img = np.zeros((100, 100), dtype=np.uint8)
        else:
            img = np.zeros((100, 100), dtype=np.uint8)
        out.write(img)

out.release()
EOF
    python3 /tmp/gen_video.py

    cat << 'EOF' > /home/user/sparse_logs.csv
timestamp,error_rate
1700000000,1.0
1700000003,2.5
1700000008,5.0
1700000015,1.2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

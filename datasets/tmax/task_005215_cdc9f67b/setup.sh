#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest numpy opencv-python-headless scipy

    mkdir -p /app

    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

r_true = 1.2
K_true = 200.0
I0 = 15.0

out = cv2.VideoWriter('/app/fluor_seq.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (100, 100), isColor=False)

def logistic(t, r, K, I0):
    return K / (1 + ((K - I0) / I0) * np.exp(-r * t))

for i in range(100):
    t = i * 0.1
    intensity = logistic(t, r_true, K_true, I0)
    frame = np.full((100, 100), int(round(intensity)), dtype=np.uint8)
    out.write(frame)

out.release()
EOF

    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

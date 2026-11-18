#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest opencv-python-headless numpy grpcio grpcio-tools

# Create /app directory and generate a sample video
mkdir -p /app
cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/sample.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (100, 100))
for i in range(30):
    # Create frames with varying intensities to ensure variance is non-zero
    frame = np.random.randint(0, 256, (100, 100, 3), dtype=np.uint8)
    out.write(frame)
out.release()
EOF
python3 /tmp/gen_video.py
rm /tmp/gen_video.py

# Create user and app directory
useradd -m -s /bin/bash user || true
mkdir -p /home/user/app

# Set permissions
chmod -R 777 /app
chmod -R 777 /home/user

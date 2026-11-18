#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install pytest numpy pandas opencv-python-headless flask requests

mkdir -p /app
mkdir -p /tmp/frames

# Generate frames using Python and OpenCV to ensure exact pixel values
python3 -c "
import numpy as np
import cv2

for i in range(100):
    val = 255 if i in [50, 51] else 100
    frame = np.full((240, 320, 3), val, dtype=np.uint8)
    cv2.imwrite(f'/tmp/frames/frame_{i:03d}.png', frame)
"

# Encode frames into a lossless mp4 video
ffmpeg -framerate 10 -i /tmp/frames/frame_%03d.png -c:v libx264 -crf 0 -pix_fmt yuv444p /app/experiment.mp4 -y
rm -rf /tmp/frames

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install pytest numpy opencv-python-headless matplotlib

mkdir -p /app/data

cat << 'EOF' > /app/oracle.py
import sys
import json

def process(input_file, output_file):
    with open(input_file, 'r') as f:
        data = json.load(f)

    if not data:
        with open(output_file, 'w') as f:
            f.write("")
        return

    smoothed = []
    for i in range(len(data)):
        start = max(0, i - 2)
        window = data[start:i+1]
        avg_x = sum(p[0] for p in window) / len(window)
        avg_y = sum(p[1] for p in window) / len(window)
        smoothed.append((avg_x, avg_y))

    mean_x = sum(p[0] for p in smoothed) / len(smoothed)
    mean_y = sum(p[1] for p in smoothed) / len(smoothed)

    centered = [(p[0] - mean_x, p[1] - mean_y) for p in smoothed]

    tokens = []
    for x, y in centered:
        if x >= 0 and y >= 0:
            tokens.append('A')
        elif x < 0 and y >= 0:
            tokens.append('B')
        elif x < 0 and y < 0:
            tokens.append('C')
        else:
            tokens.append('D')

    with open(output_file, 'w') as f:
        f.write("".join(tokens))

if __name__ == '__main__':
    process(sys.argv[1], sys.argv[2])
EOF

cat << 'EOF' > /tmp/make_video.py
import cv2
import numpy as np
import math

width, height = 640, 480
fps = 30
frames = 300

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/data/experiment.mp4', fourcc, fps, (width, height))

for i in range(frames):
    frame = np.zeros((height, width, 3), dtype=np.uint8)

    # Lissajous curve
    t = i / frames * 2 * math.pi
    x = int(width / 2 + width / 3 * math.sin(3 * t))
    y = int(height / 2 + height / 3 * math.sin(2 * t))

    # Draw red square (BGR format in OpenCV, so Red is (0, 0, 255))
    cv2.rectangle(frame, (x-10, y-10), (x+10, y+10), (0, 0, 255), -1)

    out.write(frame)

out.release()
EOF

python3 /tmp/make_video.py
rm /tmp/make_video.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

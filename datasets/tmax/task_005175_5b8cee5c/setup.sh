#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app

    # Generate calibration video
    cat << 'EOF' > /app/generate_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/calibration.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10.0, (100, 100))
for i in range(100):
    if i in [10, 25, 40, 55, 70]:
        frame = np.ones((100, 100, 3), dtype=np.uint8) * 255
    else:
        frame = np.zeros((100, 100, 3), dtype=np.uint8)
    out.write(frame)
out.release()
EOF
    python3 /app/generate_video.py
    rm /app/generate_video.py

    # Create oracle script
    cat << 'EOF' > /app/oracle_process.py
import sys
import re
import json

def process():
    text = sys.stdin.read()
    pattern = r'\[DATA\] (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z) v=(-?\d+)'
    matches = re.findall(pattern, text)

    data = []
    for t, v in matches:
        data.append((t, int(v)))

    data.sort(key=lambda x: x[0])

    W = 5
    result = []
    for i in range(len(data)):
        start = max(0, i - W + 1)
        window = [x[1] for x in data[start:i+1]]
        avg = sum(window) / len(window)
        result.append({"t": data[i][0], "v_smooth": round(avg, 1)})

    print(json.dumps(result))

if __name__ == "__main__":
    process()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

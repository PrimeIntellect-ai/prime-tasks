#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip libgl1 libglib2.0-0
pip3 install pytest opencv-python-headless numpy

mkdir -p /app
cd /app

cat << 'EOF' > generate_video.py
import cv2
import numpy as np

width, height = 400, 400
fps = 30
duration = 10 # seconds
frames = fps * duration

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/aero_mesh_sim.mp4', fourcc, fps, (width, height), False)

for i in range(frames):
    t = i / fps
    frame = np.zeros((height, width), dtype=np.uint8)

    # 2 Hz oscillation
    v1 = int(127 * np.sin(2 * np.pi * 2 * t) + 128)
    frame[0:100, 0:100] = v1

    # 5 Hz oscillation (Buggy / Divergent)
    v2 = int(127 * np.sin(2 * np.pi * 5 * t) + 128)
    frame[100:200, 100:200] = v2

    # 10 Hz oscillation
    v3 = int(127 * np.sin(2 * np.pi * 10 * t) + 128)
    frame[200:300, 200:300] = v3

    out.write(frame)

out.release()
EOF

python3 generate_video.py

cat << 'EOF' > /app/baseline_freqs.json
{
  "0,0,100,100": 2.0,
  "100,100,200,200": 5.5,
  "200,200,300,300": 10.0
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app

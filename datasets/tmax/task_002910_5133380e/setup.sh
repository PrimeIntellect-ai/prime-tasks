#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++
    pip3 install pytest numpy opencv-python-headless

    cat << 'EOF' > /tmp/setup.py
import os
import cv2
import numpy as np

os.makedirs("/app/video", exist_ok=True)
video_path = "/app/video/sensor_feed.mp4"

width, height = 64, 64
fps = 1
duration = 10
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter(video_path, fourcc, fps, (width, height), isColor=False)

intensities = [50, 100, 150, 200, 250, 20, 80, 140, 190, 220]

for i in range(duration):
    frame = np.full((height, width), intensities[i], dtype=np.uint8)
    out.write(frame)
out.release()

os.makedirs("/app/corpora/clean", exist_ok=True)
os.makedirs("/app/corpora/evil", exist_ok=True)

with open("/app/corpora/clean/log1.txt", "w") as f:
    f.write("FRAME_001 TEMP_40.0 VOLT_12.0 STAT_OK\n")
with open("/app/corpora/clean/log2.txt", "w") as f:
    f.write("FRAME_002 TEMP_80.5 VOLT_23.9 STAT_OK\n")
with open("/app/corpora/clean/log3.txt", "w") as f:
    f.write("FRAME_005 TEMP_180.0 VOLT_0.5 STAT_OK\n")

with open("/app/corpora/evil/log1.txt", "w") as f:
    f.write("FRAME_003 TEMP_150.0 VOLT_12.0 STAT_OK\n")
with open("/app/corpora/evil/log2.txt", "w") as f:
    f.write("FRAME_004 TEMP_100.0 VOLT_-2.0 STAT_OK\n")
with open("/app/corpora/evil/log3.txt", "w") as f:
    f.write("FRAME_006 TEMP_NA VOLT_12.0 STAT_ERR\n")
with open("/app/corpora/evil/log4.txt", "w") as f:
    f.write("FRAME_099 TEMP_50.0 VOLT_12.0 STAT_OK\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

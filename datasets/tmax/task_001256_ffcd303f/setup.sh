#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg imagemagick
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app/corpora/evil /app/corpora/clean

    python3 -c '
import os
import cv2
import numpy as np
import random

# Generate video
out = cv2.VideoWriter("/app/server_monitor.mp4", cv2.VideoWriter_fourcc(*"mp4v"), 1, (100, 100))
red_frame = np.zeros((100, 100, 3), dtype=np.uint8)
red_frame[:] = (0, 0, 200) # BGR: R=200, G=0, B=0
normal_frame = np.zeros((100, 100, 3), dtype=np.uint8)
normal_frame[:] = (200, 200, 200)

# Exactly 12 red frames
red_indices = set(random.sample(range(60), 12))
for i in range(60):
    if i in red_indices:
        out.write(red_frame)
    else:
        out.write(normal_frame)
out.release()

# Generate clean corpus
for i in range(50):
    with open(f"/app/corpora/clean/config_{i}.txt", "w") as f:
        f.write(f"KEY{i}=VALUE{i}\n")
        f.write("OTHER_KEY=NORMAL_TEXT\n")
        f.write("# Comment\n")
        f.write("LANG=日本語\n")

# Generate evil corpus
for i in range(50):
    with open(f"/app/corpora/evil/config_{i}.txt", "w") as f:
        if i < 15:
            f.write("PORT=80\nPORT=8080\n")
        elif i < 25:
            f.write(f"KEY{i}=VAL\u200BUE\n")
        elif i < 35:
            f.write(f"KEY{i}=VAL\u202EUE\n")
        else:
            f.write(f"KEY{i}=$(rm -rf /)\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

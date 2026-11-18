#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /tmp/setup.py
import cv2
import numpy as np
import random
import json
import os

# 1. Generate Video
out = cv2.VideoWriter('/app/deployment_monitor.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (100, 100))
red_frames = set(random.sample(range(150), 27))
for i in range(150):
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    if i in red_frames:
        frame[:] = (0, 0, 255) # BGR for Red
    else:
        frame[:] = (0, 255, 0) # BGR for Green
    out.write(frame)
out.release()

# 2. Generate Corpus
def rand_clean_ip():
    return f"10.0.0.{random.randint(1,254)}"

def rand_evil_ip():
    return f"198.51.100.{random.randint(1,254)}"

for i in range(50):
    clean_routes = [{"destination": rand_clean_ip()} for _ in range(5)]
    with open(f'/app/corpus/clean/manifest_{i}.json', 'w') as f:
        json.dump({"routes": clean_routes}, f)

    evil_routes = [{"destination": rand_clean_ip()} for _ in range(4)]
    evil_routes.append({"destination": rand_evil_ip()})
    random.shuffle(evil_routes)
    with open(f'/app/corpus/evil/manifest_{i}.json', 'w') as f:
        json.dump({"routes": evil_routes}, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

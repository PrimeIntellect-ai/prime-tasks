#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    cat << 'EOF' > /tmp/setup_corpora.py
import os
import json

os.makedirs("/app/corpora/evil", exist_ok=True)
os.makedirs("/app/corpora/clean", exist_ok=True)

# Clean 1: Normal traffic
with open("/app/corpora/clean/log1.jsonl", "w") as f:
    f.write(json.dumps({"timestamp": 1000, "user_id": "u1", "action": "update"}) + "\n")
    f.write(json.dumps({"timestamp": 1002, "user_id": "u1", "action": "update"}) + "\n")
    f.write(json.dumps({"timestamp": 1011, "user_id": "u1", "action": "update"}) + "\n") # 3 events in 11s, max is 4 in 10s

# Evil 1: Rate limit exceeded (5 events in 10s for u2)
with open("/app/corpora/evil/log1.jsonl", "w") as f:
    for i in range(5):
        f.write(json.dumps({"timestamp": 2000 + i, "user_id": "u2", "action": "update"}) + "\n")

# Evil 2: Malformed Unicode
with open("/app/corpora/evil/log2.jsonl", "w") as f:
    f.write('{"timestamp": 3000, "user_id": "u3", "action": "update\\u05G"}\n')
EOF

    cat << 'EOF' > /tmp/setup_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/status_flashes.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 1, (100, 100))
for _ in range(5):
    out.write(np.zeros((100, 100, 3), dtype=np.uint8)) # Black
for _ in range(4):
    img = np.zeros((100, 100, 3), dtype=np.uint8)
    img[:] = (0, 0, 255) # Red in BGR
    out.write(img)
for _ in range(10):
    img = np.zeros((100, 100, 3), dtype=np.uint8)
    img[:] = (0, 255, 0) # Green in BGR
    out.write(img)
out.release()
EOF

    python3 /tmp/setup_corpora.py
    python3 /tmp/setup_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

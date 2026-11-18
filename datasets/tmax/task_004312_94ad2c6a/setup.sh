#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app
    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import cv2
import numpy as np
import json
import random

# Generate video
fps = 1
width, height = 640, 480
out = cv2.VideoWriter('/app/ui_test.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (width, height))

for i in range(30):
    if i % 6 < 5:
        # Active screen (white)
        frame = np.ones((height, width, 3), dtype=np.uint8) * 255
    else:
        # Black transition
        frame = np.zeros((height, width, 3), dtype=np.uint8)
    out.write(frame)
out.release()

# Generate JSONL
records = []
windows = [(0,4), (6,10), (12,16), (18,22), (24,28)]
for w_idx, (start, end) in enumerate(windows):
    for r_idx in range(3):
        loc_key = f"screen_{w_idx}_key_{r_idx}"
        base_text = f"Translation for {loc_key}"
        for dup in range(3):
            # length variation
            text = base_text + "_" * dup
            # timestamp within start, end
            ts = random.randint(start, end)
            records.append({"timestamp": ts, "loc_key": loc_key, "text": text})

random.shuffle(records)
with open('/home/user/raw_translations.jsonl', 'w') as f:
    for r in records:
        f.write(json.dumps(r) + '\n')
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

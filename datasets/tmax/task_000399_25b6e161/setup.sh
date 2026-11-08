#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        postgresql \
        rustc \
        cargo \
        libsm6 \
        libxext6 \
        libgl1-mesa-glx

    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app/corpora/evil /app/corpora/clean

    python3 -c "
import cv2
import numpy as np
import csv
import random
import os
import json

# Generate Video
out = cv2.VideoWriter('/app/drone_feed.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (100, 100))
black = np.zeros((100, 100, 3), dtype=np.uint8)
red = np.zeros((100, 100, 3), dtype=np.uint8)
red[:] = (0, 0, 255) # BGR

for _ in range(100): out.write(black)
for _ in range(14): out.write(red)
for _ in range(386): out.write(black)
out.release()

# Generate CSV
with open('/app/raw_routes.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['edge_id', 'source_node', 'target_node', 'base_cost'])
    writer.writerow([0, 'DEPOT_ALPHA', 'NODE_1', 1.0])
    for i in range(1, 9999):
        writer.writerow([i, f'NODE_{i}', f'NODE_{i+1}', random.uniform(1.0, 10.0)])
    writer.writerow([9999, 'NODE_9999', 'DISTRIBUTION_ZETA', 1.0])

# Generate Corpora
for i in range(50):
    with open(f'/app/corpora/evil/evil_{i}.json', 'w') as f:
        json.dump({'query_filter': 'DROP TABLE routes' if i % 2 == 0 else '../../etc/passwd'}, f)
    with open(f'/app/corpora/clean/clean_{i}.json', 'w') as f:
        json.dump({'query_filter': f'filter_{i}'}, f)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

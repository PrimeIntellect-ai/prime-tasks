#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl cargo libgl1 libglib2.0-0
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app/corpus/evil /app/corpus/clean

    cat << 'EOF' > /tmp/setup.py
import cv2
import numpy as np
import json
import os

os.makedirs('/app/corpus/evil', exist_ok=True)
os.makedirs('/app/corpus/clean', exist_ok=True)

# Generate adjacency matrix
adj = np.zeros((20, 20), dtype=np.uint8)
hubs = [4, 9, 14]
for h in hubs:
    for i in range(20):
        if i != h:
            adj[h, i] = 1
            adj[i, h] = 1

# Video generation
out = cv2.VideoWriter('/app/topology_scan.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 1, (100, 100), isColor=True)
for f in range(30):
    frame = np.ones((100, 100, 3), dtype=np.uint8) * 255
    for i in range(20):
        for j in range(20):
            if adj[i, j] == 1:
                frame[j, i] = [0, 0, 0] # x=i, y=j -> frame[j, i]
    out.write(frame)
out.release()

# Generate JSON
evil_data = [
    {"tx_id": "1", "timestamp_sec": 10, "router_id": 4, "bytes": 4000},
    {"tx_id": "2", "timestamp_sec": 20, "router_id": 4, "bytes": 4000},
    {"tx_id": "3", "timestamp_sec": 30, "router_id": 4, "bytes": 4000}
]
with open('/app/corpus/evil/evil1.json', 'w') as f:
    json.dump(evil_data, f)

clean_data1 = [
    {"tx_id": "1", "timestamp_sec": 10, "router_id": 4, "bytes": 2000},
    {"tx_id": "2", "timestamp_sec": 20, "router_id": 4, "bytes": 2000},
    {"tx_id": "3", "timestamp_sec": 30, "router_id": 4, "bytes": 2000}
]
with open('/app/corpus/clean/clean1.json', 'w') as f:
    json.dump(clean_data1, f)

clean_data2 = [
    {"tx_id": "1", "timestamp_sec": 10, "router_id": 1, "bytes": 4000},
    {"tx_id": "2", "timestamp_sec": 20, "router_id": 1, "bytes": 4000},
    {"tx_id": "3", "timestamp_sec": 30, "router_id": 1, "bytes": 4000}
]
with open('/app/corpus/clean/clean2.json', 'w') as f:
    json.dump(clean_data2, f)
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

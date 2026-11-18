#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libzbar0
    pip3 install pytest opencv-python-headless qrcode numpy Pillow pyzbar

    mkdir -p /app

    cat << 'EOF' > /tmp/generate_video.py
import cv2
import qrcode
import json
import numpy as np
import random

edges = []
random.seed(42)
for tx in range(1, 16):
    nodes = [f"Job_{i}" for i in range(10)]
    if tx in [3, 7, 12]:
        # Create a cycle
        edges.append({"tx_id": tx, "source": "Job_0", "target": "Job_1", "duration_ms": 10})
        edges.append({"tx_id": tx, "source": "Job_1", "target": "Job_2", "duration_ms": 10})
        edges.append({"tx_id": tx, "source": "Job_2", "target": "Job_0", "duration_ms": 10})
    else:
        # Create a simple DAG path
        edges.append({"tx_id": tx, "source": "Job_0", "target": "Job_1", "duration_ms": 10})
        edges.append({"tx_id": tx, "source": "Job_1", "target": "Job_2", "duration_ms": 10})

    # Add some random edges
    for _ in range(5):
        s = random.choice(nodes)
        t = random.choice(nodes)
        if s != t:
            edges.append({"tx_id": tx, "source": s, "target": t, "duration_ms": random.randint(5, 50)})

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/etl_monitor.mp4', fourcc, 10.0, (400, 400))

frame_idx = 0
edge_idx = 0
for _ in range(600):
    img = np.zeros((400, 400, 3), dtype=np.uint8)
    if frame_idx % 5 == 0 and edge_idx < len(edges):
        data = json.dumps(edges[edge_idx])
        qr = qrcode.make(data)
        qr_img = np.array(qr.convert('RGB'))
        qr_img = cv2.resize(qr_img, (200, 200))
        img[100:300, 100:300] = qr_img
        edge_idx += 1
    out.write(img)
    frame_idx += 1

out.release()
EOF

    python3 /tmp/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

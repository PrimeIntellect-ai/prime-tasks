#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libzbar0
    pip3 install pytest "numpy<2" opencv-python-headless qrcode pillow pyzbar

    mkdir -p /app
    mkdir -p /home/user

    cat << 'EOF' > /app/generate.py
import cv2
import qrcode
import numpy as np
import json
import random

random.seed(42)
nodes = ["IP_EXT_994"] + [f"System_{i:03d}" for i in range(100)] + [f"Router_{i}" for i in range(20)]

edges = []
ts = 1000
current_level = ["IP_EXT_994"]
next_level = []
for _ in range(60):
    src = random.choice(current_level)
    dst = random.choice(nodes)
    if dst != src:
        edges.append({"src": src, "dst": dst, "ts": ts, "action": "login"})
        ts += random.randint(1, 10)
        next_level.append(dst)
        if len(next_level) > 10:
            current_level = next_level
            next_level = []

scores = {n: 0 for n in nodes if n.startswith("System_")}

def dfs(node, current_ts, path):
    if node.startswith("System_"):
        scores[node] += 1
    for e in edges:
        if e["src"] == node and e["ts"] >= current_ts:
            dfs(e["dst"], e["ts"], path + [e])

dfs("IP_EXT_994", 0, [])

sorted_systems = sorted([n for n in scores.keys()], key=lambda x: (-scores[x], x))
top_50 = sorted_systems[:50]

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/audit_stream.mp4', fourcc, 30.0, (400, 400))

edge_idx = 0
for frame_idx in range(300):
    img = np.zeros((400, 400, 3), dtype=np.uint8)
    if frame_idx % 5 == 0 and edge_idx < len(edges):
        data = json.dumps(edges[edge_idx])
        qr = qrcode.make(data)
        qr_img = np.array(qr.convert('RGB'))
        qr_img = cv2.resize(qr_img, (400, 400))
        img = qr_img
        edge_idx += 1
    out.write(img)
out.release()

with open('/app/verifier.py', 'w') as f:
    f.write(f'''import csv
import sys

REFERENCE_TOP_50 = {set(top_50)}

try:
    agent_systems = set()
    with open('/home/user/vulnerable_systems.csv', 'r') as f:
        reader = csv.reader(f)
        next(reader)
        for row in reader:
            if row[0].startswith("System_"):
                agent_systems.add(row[0])
            if len(agent_systems) == 50:
                break

    intersection = len(REFERENCE_TOP_50.intersection(agent_systems))
    union = len(REFERENCE_TOP_50.union(agent_systems))

    iou = intersection / union if union > 0 else 0.0
    print(iou)
except Exception as e:
    print(0.0)
''')
EOF

    python3 /app/generate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

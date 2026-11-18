#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg libsm6 libxext6
pip3 install pytest opencv-python-headless numpy

mkdir -p /app

cat << 'EOF' > /app/generate_video.py
import cv2
import numpy as np
import random

width, height = 64, 64
fps = 30
duration = 10
total_frames = fps * duration

green_frames = set(random.sample(range(total_frames), 7))

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/query_viz.mp4', fourcc, fps, (width, height))

for i in range(total_frames):
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    if i in green_frames:
        frame[:] = (0, 255, 0) # BGR format: Green is at index 1
    out.write(frame)

out.release()
EOF

python3 /app/generate_video.py

cat << 'EOF' > /app/oracle.py
import sys
import json
from collections import defaultdict

def solve():
    N = 7
    try:
        data = json.loads(sys.stdin.read().strip())
    except:
        return

    nodes = {n['id']: n for n in data.get('nodes', [])}
    adj = defaultdict(list)
    for e in data.get('edges', []):
        adj[e['source']].append(e['target'])
        adj[e['target']].append(e['source'])

    valid_users = set()
    for node_id, node in nodes.items():
        if node.get('type') == 'User':
            for neighbor_id in adj[node_id]:
                neighbor = nodes.get(neighbor_id)
                if neighbor and neighbor.get('type') == 'Product' and neighbor.get('price', 0) > N:
                    valid_users.add(node_id)
                    break

    sorted_users = sorted(list(valid_users), reverse=True)[:5]
    if sorted_users:
        print(",".join(sorted_users))
    else:
        print()

if __name__ == "__main__":
    solve()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

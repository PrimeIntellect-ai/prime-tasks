#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libsm6 libxext6
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app

    cat << 'EOF' > /app/setup_video.py
import cv2
import numpy as np
import random

random.seed(42)
width, height = 64, 64
fps = 10
frames = 100

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/data_stream.mp4', fourcc, fps, (width, height))

edges = []
# Generate random graph edges
for _ in range(frames):
    r = random.randint(0, 50)  # limit node IDs to increase connectivity
    g = random.randint(0, 50)
    b = random.randint(0, 255) # weights
    edges.append((r, g, b))

    # OpenCV uses BGR
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    frame[:] = (b, g, r) 
    out.write(frame)

out.release()
EOF

    python3 /app/setup_video.py

    cat << 'EOF' > /app/oracle_graph.py
import sys
import json
import cv2

def main():
    start_node = int(sys.argv[1])
    weight_limit = int(sys.argv[2])

    cap = cv2.VideoCapture('/app/data_stream.mp4')
    edges = []
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        # frame is BGR
        b, g, r = frame[0, 0]
        edges.append((int(r), int(g), int(b)))
    cap.release()

    # Filter edges
    filtered_edges = [e for e in edges if e[2] <= weight_limit]

    # Adjacency list for filtered graph
    adj = {}
    for r, g, b in filtered_edges:
        if r not in adj: adj[r] = []
        if g not in adj: adj[g] = []
        adj[r].append(g)

    if start_node not in adj:
        print(json.dumps({"reachable_count": 1, "max_out_node": start_node}))
        return

    # BFS
    reachable = set([start_node])
    queue = [start_node]
    while queue:
        curr = queue.pop(0)
        for neighbor in adj.get(curr, []):
            if neighbor not in reachable:
                reachable.add(neighbor)
                queue.append(neighbor)

    # Calculate out-degrees in filtered graph for reachable nodes only
    best_node = min(reachable)
    max_out = -1

    for node in reachable:
        out_deg = len(adj.get(node, []))
        if out_deg > max_out:
            max_out = out_deg
            best_node = node
        elif out_deg == max_out:
            if node < best_node:
                best_node = node

    print(json.dumps({"reachable_count": len(reachable), "max_out_node": best_node}))

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

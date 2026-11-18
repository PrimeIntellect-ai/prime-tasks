#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make ffmpeg
    pip3 install pytest numpy networkx opencv-python-headless

    mkdir -p /app

    cat << 'EOF' > /tmp/setup.py
import os
import cv2
import numpy as np
import csv
import networkx as nx

os.makedirs("/app", exist_ok=True)

graph_file = "/app/network_graph.csv"
edges = []
np.random.seed(42)

for i in range(100):
    if i % 10 != 9:
        edges.append((i, i+1, np.random.randint(1, 10)))
    if i < 90:
        edges.append((i, i+10, np.random.randint(1, 10)))

for _ in range(20):
    u = np.random.randint(0, 100)
    v = np.random.randint(0, 100)
    if u != v:
        edges.append((u, v, np.random.randint(10, 50)))

with open(graph_file, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['source', 'destination', 'weight'])
    for u, v, w in edges:
        writer.writerow([u, v, w])

G = nx.Graph()
for u, v, w in edges:
    G.add_edge(u, v, weight=w)

paths = nx.single_source_dijkstra_path_length(G, 0)

video_file = "/app/network_status.mp4"
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter(video_file, fourcc, 1.0, (100, 100))

target_nodes = [
    5, 12, 45, 99, 34, 76, 21, 8, 55, 67, 
    89, 2, 19, 44, 77, 88, 91, 10, 3, 30,
    50, 60, 70, 80, 90, 15, 25, 35, 42, 95
]

truth_file = "/app/ground_truth.txt"
with open(truth_file, "w") as f:
    for frame_id, node_id in enumerate(target_nodes):
        cost = paths.get(node_id, -1)
        f.write(f"{frame_id},{node_id},{cost}\n")

for node_id in target_nodes:
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    y = (node_id // 10) * 10
    x = (node_id % 10) * 10
    frame[y:y+10, x:x+10] = (0, 0, 255)
    out.write(frame)

out.release()
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

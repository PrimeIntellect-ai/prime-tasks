#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libglib2.0-0
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app

    # Generate the reference video using python instead of ffmpeg to avoid syntax/filter issues
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

fps = 60
duration = 10
frames = fps * duration
width, height = 64, 64

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/reference_experiment.mp4', fourcc, fps, (width, height), isColor=False)

for i in range(frames):
    t = i / fps
    val = int(128 + 127 * np.sin(2 * np.pi * 5.0 * t))
    val = max(0, min(255, val))
    frame = np.full((height, width), val, dtype=np.uint8)
    out.write(frame)

out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    mkdir -p /home/user/sim

    cat << 'EOF' > /home/user/sim/test_graph.json
{
  "nodes": [0, 1, 2, 3],
  "edges": [[0, 1], [1, 2], [2, 3], [3, 0]]
}
EOF

    cat << 'EOF' > /home/user/sim/vibration_sim.py
import json
import math

def calculate_forces(positions, edges):
    # Buggy representation: adjacency list as sets (unordered)
    adj = {}
    for u, v in edges:
        adj.setdefault(u, set()).add(v)
        adj.setdefault(v, set()).add(u)

    forces = [0.0] * len(positions)
    # The iteration order over set() is non-deterministic.
    # Floating point addition is not associative: (a+b)+c != a+(b+c)
    for node, neighbors in adj.items():
        for neighbor in neighbors:
            # Hooke's law type spring force
            forces[node] += (positions[neighbor] - positions[node]) * 0.1
    return forces

def run_simulation(graph_data):
    nodes = graph_data['nodes']
    edges = graph_data['edges']
    positions = [float(i) for i in range(len(nodes))]
    velocities = [0.0] * len(nodes)
    velocities[0] = 1.0 # Kick the first node

    history = []
    # Integration loop
    for _ in range(1000):
        forces = calculate_forces(positions, edges)
        for i in range(len(nodes)):
            velocities[i] += forces[i] * 0.01
            positions[i] += velocities[i] * 0.01
        history.append(positions[0])

    # Calculate frequency of node 0 (simplified zero-crossings for this test)
    crossings = 0
    for i in range(1, len(history)):
        if history[i-1] < 0 and history[i] >= 0:
            crossings += 1
    # 1000 steps * 0.01 dt = 10 seconds.
    return crossings / 10.0
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr fonts-liberation
    pip3 install pytest pillow

    mkdir -p /app

    # Generate the video fixture
    cat << 'EOF' > /tmp/gen_video.py
import os
from PIL import Image, ImageDraw, ImageFont
import subprocess

edges = [
    "LOBBY <-> HALL_1", "HALL_1 <-> SERVER_ROOM", "HALL_1 <-> CAFETARIA",
    "CAFETARIA <-> PATIO", "LOBBY <-> HALL_2", "HALL_2 <-> HR_OFFICE",
    "HR_OFFICE <-> EXEC_SUITE", "SERVER_ROOM <-> BACK_ALLEY",
    "HALL_2 <-> IT_STORAGE", "IT_STORAGE <-> SERVER_ROOM",
    "PATIO <-> SMOKING_AREA", "EXEC_SUITE <-> BALCONY",
    "LOBBY <-> SECURITY_DESK", "SECURITY_DESK <-> CAMERA_ROOM",
    "CAMERA_ROOM <-> SERVER_ROOM"
]

os.makedirs("/tmp/frames", exist_ok=True)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 40)
except:
    font = ImageFont.load_default()

for i, text in enumerate(edges):
    img = Image.new('RGB', (800, 200), color='white')
    d = ImageDraw.Draw(img)
    d.text((50, 80), text, fill='black', font=font)
    img.save(f"/tmp/frames/frame_{i:03d}.png")

subprocess.run([
    "ffmpeg", "-y", "-framerate", "1", "-i", "/tmp/frames/frame_%03d.png",
    "-c:v", "libx264", "-r", "1", "-pix_fmt", "yuv420p", "/app/cctv_topology.mp4"
], check=True)
EOF
    python3 /tmp/gen_video.py
    rm -rf /tmp/frames /tmp/gen_video.py

    # Create the oracle script
    cat << 'EOF' > /app/oracle_path_check.py
import sys
from collections import deque

edges = [
    ("LOBBY", "HALL_1"), ("HALL_1", "SERVER_ROOM"), ("HALL_1", "CAFETARIA"),
    ("CAFETARIA", "PATIO"), ("LOBBY", "HALL_2"), ("HALL_2", "HR_OFFICE"),
    ("HR_OFFICE", "EXEC_SUITE"), ("SERVER_ROOM", "BACK_ALLEY"),
    ("HALL_2", "IT_STORAGE"), ("IT_STORAGE", "SERVER_ROOM"),
    ("PATIO", "SMOKING_AREA"), ("EXEC_SUITE", "BALCONY"),
    ("LOBBY", "SECURITY_DESK"), ("SECURITY_DESK", "CAMERA_ROOM"),
    ("CAMERA_ROOM", "SERVER_ROOM")
]

graph = {}
for u, v in edges:
    graph.setdefault(u, []).append(v)
    graph.setdefault(v, []).append(u)

def bfs(start, end):
    if start not in graph or end not in graph: return "NO_PATH"
    if start == end: return start
    queue = deque([[start]])
    visited = set([start])

    while queue:
        path = queue.popleft()
        node = path[-1]

        # Sort neighbors to ensure deterministic shortest path choice for fuzz equivalence
        for neighbor in sorted(graph.get(node, [])):
            if neighbor == end:
                return ",".join(path + [neighbor])
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append(path + [neighbor])
    return "NO_PATH"

if __name__ == "__main__":
    if len(sys.argv) != 3: sys.exit(1)
    print(bfs(sys.argv[1], sys.argv[2]))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 755 /app

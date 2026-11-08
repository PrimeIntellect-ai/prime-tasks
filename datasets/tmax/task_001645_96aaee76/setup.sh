#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc libc6-dev
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app/corpus/clean /app/corpus/evil /app/incoming

    cat << 'EOF' > /tmp/setup.py
import os
import random
import cv2
import numpy as np

# Generate Video
fps = 30
duration = 10
total_frames = fps * duration
black_frames_count = 7
width, height = 640, 480

out = cv2.VideoWriter('/app/incident.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (width, height))

black_indices = set(random.sample(range(total_frames), black_frames_count))

for i in range(total_frames):
    if i in black_indices:
        frame = np.zeros((height, width, 3), dtype=np.uint8)
    else:
        frame = np.full((height, width, 3), 128, dtype=np.uint8)
        cv2.putText(frame, f"CAM 1 - Frame {i}", (50, 50), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
    out.write(frame)
out.release()

# Generate Corpus
def make_file(path, is_evil, evil_type="length"):
    body = "Hello World! This is a test payload."
    user_agent = "Mozilla/5.0"
    content_length = len(body.encode('utf-8'))

    if is_evil:
        if evil_type == "length":
            content_length += 10 # Mismatch
        elif evil_type == "ua":
            user_agent = "curl/7.68.0; rm -rf /"

    content = f"User-Agent: {user_agent}\nContent-Length: {content_length}\n\n{body}"
    with open(path, "w") as f:
        f.write(content)

for i in range(50):
    make_file(f"/app/corpus/clean/clean_{i}.txt", False)

for i in range(25):
    make_file(f"/app/corpus/evil/evil_len_{i}.txt", True, "length")
    make_file(f"/app/corpus/evil/evil_ua_{i}.txt", True, "ua")

for i in range(10):
    make_file(f"/app/incoming/clean_{i}.txt", False)
    # Mix of evil types for incoming
    if i < 5:
        make_file(f"/app/incoming/evil_{i}.txt", True, "length")
    else:
        make_file(f"/app/incoming/evil_{i}.txt", True, "ua")

EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user

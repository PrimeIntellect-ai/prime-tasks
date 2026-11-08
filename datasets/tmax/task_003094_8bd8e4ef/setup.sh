#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg cargo curl
    pip3 install pytest numpy

    mkdir -p /app

    # Generate the video fixture
    cat << 'EOF' > /app/generate_video.py
import numpy as np
import subprocess
import random

frames = 1000
width = 128
height = 128

raw_bytes = bytearray()
for _ in range(frames):
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    r = random.randint(0, 255)
    g = random.randint(0, 255)
    b = random.choice([0, 1])
    frame[64, 64] = [r, g, b]
    raw_bytes.extend(frame.tobytes())

cmd = [
    "ffmpeg", "-y",
    "-f", "rawvideo",
    "-vcodec", "rawvideo",
    "-s", f"{width}x{height}",
    "-pix_fmt", "rgb24",
    "-r", "25",
    "-i", "-",
    "-c:v", "libx264rgb",
    "-crf", "0",
    "/app/audit_log.mp4"
]
subprocess.run(cmd, input=raw_bytes, check=True, stderr=subprocess.DEVNULL)
EOF
    python3 /app/generate_video.py

    # Create oracle
    cat << 'EOF' > /app/oracle_audit
#!/usr/bin/env python3
import sys
import subprocess
from collections import defaultdict

if len(sys.argv) != 3:
    sys.exit(1)

start_frame = int(sys.argv[1])
end_frame = int(sys.argv[2])

cmd = [
    "ffmpeg", "-i", "/app/audit_log.mp4",
    "-vf", f"select='between(n\,{start_frame}\,{end_frame})'",
    "-f", "image2pipe", "-vcodec", "rawvideo", "-pix_fmt", "rgb24", "-"
]

out = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout

out_degree = defaultdict(int)
frame_size = 128 * 128 * 3
center_offset = (64 * 128 + 64) * 3

for i in range(0, len(out), frame_size):
    frame = out[i:i+frame_size]
    if len(frame) < frame_size:
        break
    r = frame[center_offset]
    g = frame[center_offset+1]
    b = frame[center_offset+2]

    if b == 1:
        out_degree[r] += 1

if not out_degree:
    print("0,0")
else:
    max_deg = max(out_degree.values())
    candidates = [node for node, deg in out_degree.items() if deg == max_deg]
    print(f"{min(candidates)},{max_deg}")
EOF
    chmod +x /app/oracle_audit

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

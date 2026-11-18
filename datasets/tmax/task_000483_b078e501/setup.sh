#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk ffmpeg
    pip3 install pytest numpy

    mkdir -p /app

    cat << 'EOF' > /tmp/gen_video.py
import numpy as np
import subprocess

N = 300
fps = 30
width, height = 64, 64

frames = []
for t in range(N):
    val = 128 + 40 * np.cos(2 * np.pi * 5 * t / 300)
    frame = np.full((height, width), int(val), dtype=np.uint8)
    frames.append(frame)

raw_bytes = b''.join([f.tobytes() for f in frames])

cmd = [
    'ffmpeg', '-y',
    '-f', 'rawvideo',
    '-vcodec', 'rawvideo',
    '-s', f'{width}x{height}',
    '-pix_fmt', 'gray',
    '-r', str(fps),
    '-i', '-',
    '-c:v', 'libx264',
    '-pix_fmt', 'yuv420p',
    '/app/pulsar.mp4'
]

subprocess.run(cmd, input=raw_bytes, check=True)
EOF

    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

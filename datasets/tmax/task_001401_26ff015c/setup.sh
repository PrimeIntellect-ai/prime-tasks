#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc
    pip3 install pytest

    mkdir -p /app/frames
    cat << 'EOF' > /app/generate_video.py
import os
import random
import subprocess

x, y = 50.0, 50.0
for i in range(50):
    with open(f"/app/frames/{i:03d}.pgm", "w") as f:
        f.write("P2\n100 100\n255\n")
        for ry in range(100):
            for rx in range(100):
                if rx == int(x) and ry == int(y):
                    f.write("255 ")
                else:
                    f.write("0 ")
            f.write("\n")
    # D = 15.0, variance = 2D = 30.0 for each dimension
    x += random.gauss(0, 30.0**0.5)
    y += random.gauss(0, 30.0**0.5)
    x = max(0, min(99, x))
    y = max(0, min(99, y))

subprocess.run(["ffmpeg", "-y", "-framerate", "10", "-i", "/app/frames/%03d.pgm", "-c:v", "libx264", "-pix_fmt", "yuv420p", "/app/fluor_seq.mp4"], check=True)
EOF
    python3 /app/generate_video.py
    rm -rf /app/frames /app/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

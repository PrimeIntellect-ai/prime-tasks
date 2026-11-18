#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc
    pip3 install pytest

    mkdir -p /app/adversarial/clean
    mkdir -p /app/adversarial/evil

    cat << 'EOF' > /tmp/setup.py
import os
import subprocess

# Generate CSV files
header = "id,measurement,category_token\n"

for i in range(10):
    with open(f"/app/adversarial/clean/clean_{i}.csv", "w") as f:
        f.write(header)
        f.write(f"1,0.5,10\n2,0.6,42\n3,0.7,1\n")

evil_tokens = ["5.0", "NaN", "Inf", "0", "-1", "3.14", "0.0", "-5.5", "NaN", "10.0"]
for i in range(10):
    with open(f"/app/adversarial/evil/evil_{i}.csv", "w") as f:
        f.write(header)
        f.write(f"1,0.5,10\n2,0.6,{evil_tokens[i]}\n3,0.7,1\n")

# Generate video frames
os.makedirs("/app/frames", exist_ok=True)
for i in range(50):
    color = "255 255 255" if i in [14, 27, 41] else "0 0 0"
    with open(f"/app/frames/frame_{i:03d}.ppm", "w") as f:
        f.write(f"P3\n10 10\n255\n")
        for _ in range(100):
            f.write(f"{color}\n")

# Encode video
subprocess.run([
    "ffmpeg", "-y", "-framerate", "10", 
    "-i", "/app/frames/frame_%03d.ppm", 
    "-c:v", "libx264", "-pix_fmt", "yuv420p", 
    "/app/sync_video.mp4"
], check=True)

EOF

    python3 /tmp/setup.py
    rm -rf /app/frames /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

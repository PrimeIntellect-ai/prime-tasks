#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg bc gawk sed coreutils
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import random
import subprocess

# Generate video frames
os.makedirs("/tmp/frames", exist_ok=True)
for i in range(1, 21):
    color = "white" if i == 14 else "black"
    subprocess.run(f"ffmpeg -y -f lavfi -i color=c={color}:s=100x100 -vframes 1 /tmp/frames/frame_{i:03d}.png", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# Encode video
subprocess.run("ffmpeg -y -framerate 10 -i /tmp/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/electrophoresis.mp4", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# Generate trace files
for i in range(10):
    # Clean trace
    vals_clean = [round(random.uniform(0.1, 10.0), 4) for _ in range(15)]
    total_clean = sum(int(v * 10000) for v in vals_clean) / 10000.0
    with open(f"/app/corpus/clean/trace_{i}.txt", "w") as f:
        f.write(f"# SUM: {total_clean:.4f}\n")
        random.shuffle(vals_clean)
        for v in vals_clean:
            f.write(f"{v:.4f}\n")

    # Evil trace (sum off by 0.0001)
    vals_evil = [round(random.uniform(0.1, 10.0), 4) for _ in range(15)]
    total_evil = (sum(int(v * 10000) for v in vals_evil) + random.choice([-1, 1])) / 10000.0
    with open(f"/app/corpus/evil/trace_{i}.txt", "w") as f:
        f.write(f"# SUM: {total_evil:.4f}\n")
        random.shuffle(vals_evil)
        for v in vals_evil:
            f.write(f"{v:.4f}\n")
EOF

    python3 /tmp/setup.py
    rm -rf /tmp/setup.py /tmp/frames

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

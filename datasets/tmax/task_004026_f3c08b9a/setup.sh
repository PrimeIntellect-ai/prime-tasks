#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required system packages
    apt-get install -y ffmpeg imagemagick gawk sqlite3

    # Create directories
    mkdir -p /app
    mkdir -p /tmp/extract

    # Generate synthetic video and ground truth
    cat << 'EOF' > /tmp/setup.py
import os
import subprocess
import json

os.makedirs('/app', exist_ok=True)

# Generate 30 frames with varying grayscale colors
for i in range(1, 31):
    gray_val = (i % 10) * 10 # 0 to 90 percent
    subprocess.run(["convert", "-size", "100x100", f"xc:gray({gray_val}%)", f"/tmp/frame_{i:03d}.png"], check=True)

# Combine frames into a video at 1 fps
subprocess.run(["ffmpeg", "-y", "-framerate", "1", "-i", "/tmp/frame_%03d.png", "-c:v", "libx264", "-pix_fmt", "yuv420p", "/app/sync_dashboard.mp4"], check=True)

# Extract frames to compute exact ground truth
subprocess.run(["ffmpeg", "-i", "/app/sync_dashboard.mp4", "-vf", "fps=1", "/tmp/extract/frame_%03d.png"], check=True)

data = []
intensities = []
for i in range(1, 31):
    res = subprocess.run(["convert", f"/tmp/extract/frame_{i:03d}.png", "-colorspace", "gray", "-format", "%[fx:mean]", "info:"], capture_output=True, text=True)
    try:
        intensity = float(res.stdout.strip())
    except ValueError:
        intensity = 0.0
    intensities.append(intensity)

    # 5-second rolling moving average
    start = max(0, i - 5)
    window = intensities[start:i]
    moving_avg = sum(window) / len(window)

    data.append({
        "second": i,
        "intensity": intensity,
        "moving_avg": moving_avg
    })

with open('/app/ground_truth_stats.json', 'w') as f:
    json.dump(data, f)
EOF

    python3 /tmp/setup.py
    rm -rf /tmp/frame_*.png /tmp/extract /tmp/setup.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

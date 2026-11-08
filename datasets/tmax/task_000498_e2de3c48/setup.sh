#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest pandas numpy opencv-python-headless

    mkdir -p /app

    # Create experiment.mp4 (30 seconds) using ultrafast preset to avoid timeout
    ffmpeg -y -f lavfi -i color=c=blue:s=640x480:r=30:d=30 -c:v libx264 -preset ultrafast -pix_fmt yuv420p /app/experiment.mp4

    # Create telemetry.csv
    cat << 'EOF' > /app/telemetry.csv
timestamp,speed,lat,lon
EOF
    for i in $(seq 0 60); do
        echo "$i,15.5,37.7750,-122.4195" >> /app/telemetry.csv
    done

    # Create baseline_inference.py
    cat << 'EOF' > /app/baseline_inference.py
import sys
import time
import numpy as np
import hashlib

def process(image_path):
    # Simulate heavy inference load
    img_hash = int(hashlib.md5(open(image_path, 'rb').read()).hexdigest(), 16)
    np.random.seed(img_hash % (2**32))
    A = np.random.randn(800, 800)
    B = np.random.randn(800, 800)
    C = A @ B
    return int(np.sum(C) % 15)

if __name__ == "__main__":
    t0 = time.time()
    res = process(sys.argv[1])
    t1 = time.time()
    print(f"{sys.argv[1]},{res},{t1-t0}")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

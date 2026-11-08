#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest numpy opencv-python-headless

    mkdir -p /app

    # Generate the video
    cat << 'EOF' > /app/generate_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/spectroscopy.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 1, (100, 100), False)
for i in range(10):
    frame = np.zeros((100, 100), dtype=np.uint8)
    if i == 4:
        frame.fill(255) # Peak frame
    else:
        frame.fill(10 * i)
    out.write(frame)
out.release()
EOF
    python3 /app/generate_video.py

    # Create the oracle analyzer
    cat << 'EOF' > /app/oracle_analyzer
#!/usr/bin/env python3
import sys
import numpy as np

def main():
    line = sys.stdin.read().strip()
    if not line:
        return
    data = np.array([float(x) for x in line.split(',')])

    # Moving average size 3
    if len(data) < 3:
        return
    smoothed = np.convolve(data, np.ones(3)/3.0, mode='valid')

    np.random.seed(42)
    means = []
    for _ in range(1000):
        sample = np.random.choice(smoothed, size=len(smoothed), replace=True)
        means.append(np.mean(sample))

    lower = np.percentile(means, 2.5)
    upper = np.percentile(means, 97.5)

    print(f"CI: [{lower:.4f}, {upper:.4f}]")

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_analyzer

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-numpy python3-opencv
pip3 install --default-timeout=100 pytest

mkdir -p /app
cat << 'EOF' > /app/annotations.txt
The quick brown fox jumps over the lazy dog!
Experiment 1: System initiated. All systems nominal.
Wait, what is happening? Anomaly detected at 30ms.
Calibration matrix: 0.99, 0.01, 0.00.
Red light flashes, green light stays steady.
Test sequence #54 is now running in the background.
Data throughput increased by 20% compared to baseline.
Sensors indicate temperature drop: -5 degrees Celsius.
Approaching terminal velocity; prepare for impact.
Simulation concluded. Data saved to /tmp/out.dat successfully.
EOF

cat << 'EOF' > /tmp/make_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/experiment_record.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (64, 64))
np.random.seed(42)

for sec in range(10):
    # Base color for the second
    base_color = np.random.randint(50, 200, size=(3,))
    for frame in range(30):
        # Add some noise to make covariance non-zero
        noise = np.random.randn(64, 64, 3) * 10
        img = np.clip(base_color + noise, 0, 255).astype(np.uint8)
        out.write(img)

out.release()
EOF
python3 /tmp/make_video.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

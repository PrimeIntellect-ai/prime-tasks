#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import os
import cv2

# Generate deterministic weights
np.random.seed(42)
W = np.random.randn(3072, 16) * 0.1
b = np.random.randn(16) * 0.1
np.savez('/home/user/model_weights.npz', W=W, b=b)
os.chmod('/home/user/model_weights.npz', 0o644)

# Create the oracle script
oracle_code = """#!/usr/bin/env python3
import sys
import cv2
import numpy as np

def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    try:
        frame_idx = int(sys.argv[1])
    except ValueError:
        print(",".join(["0.0000"] * 16))
        return

    cap = cv2.VideoCapture('/app/experiment_record.mp4')

    # Check bounds
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    if frame_idx < 0 or frame_idx >= total_frames:
        print(",".join(["0.0000"] * 16))
        return

    cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
    ret, frame = cap.read()

    if not ret:
        print(",".join(["0.0000"] * 16))
        return

    patch = frame[0:32, 0:32, :]
    vec = patch.flatten().astype(np.float64) / 255.0

    weights = np.load('/home/user/model_weights.npz')
    W = weights['W']
    b = weights['b']

    z = np.dot(vec, W) + b
    emb = np.maximum(0, z)

    output = ",".join([f"{v:.4f}" for v in emb])
    print(output)

if __name__ == '__main__':
    main()
"""

with open('/app/oracle_extract_embeddings.py', 'w') as f:
    f.write(oracle_code)

os.chmod('/app/oracle_extract_embeddings.py', 0o755)

# Generate a simple 2-second dummy video
if not os.path.exists('/app/experiment_record.mp4'):
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter('/app/experiment_record.mp4', fourcc, 30.0, (100, 100))
    for i in range(120):
        frame = np.zeros((100, 100, 3), dtype=np.uint8)
        cv2.circle(frame, (50, 50), i % 50, (255, i * 2, 0), -1)
        out.write(frame)
    out.release()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy scipy opencv-python-headless flask requests fastapi uvicorn

mkdir -p /app
cat << 'EOF' > /tmp/gen.py
import cv2
import numpy as np

# Generate PDB file
with open('/app/tracer.pdb', 'w') as f:
    for i in range(1, 241):
        f.write(f"ATOM  {i:5d}  CA  ALA A {i:4d}    10.000  10.000  10.000  1.00  0.00           C\n")

# Generate Video file
width, height = 500, 100
fps = 30
duration = 10
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/diffusion.mp4', fourcc, fps, (width, height), False)

for i in range(fps * duration):
    t = i / fps
    sigma_sq = 2 * 45.0 * t + 10.0
    sigma = np.sqrt(sigma_sq)

    x = np.arange(width)
    profile = 255 * np.exp(-0.5 * ((x - 250) / sigma)**2)
    profile = np.clip(profile, 0, 255).astype(np.uint8)

    frame = np.tile(profile, (height, 1))
    out.write(frame)

out.release()
EOF

python3 /tmp/gen.py

useradd -m -s /bin/bash user || true
mkdir -p /home/user/workspace
chmod -R 777 /home/user
chmod -R 777 /app

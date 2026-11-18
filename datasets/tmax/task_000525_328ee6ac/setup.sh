#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang python3-pil
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /tmp/frames

    # Generate frames based on the binary sequence
    # A = 40 -> 000000101000
    # B = 130 -> 000010000010
    # C = 242 -> 000011110010
    # Sequence: 000000101000 000010000010 000011110010
    cat << 'EOF' > /tmp/gen_frames.py
import os
from PIL import Image

bits = "000000101000000010000010000011110010"
for i, bit in enumerate(bits):
    color = (255, 255, 255) if bit == '1' else (0, 0, 0)
    img = Image.new('RGB', (64, 64), color)
    img.save(f"/tmp/frames/frame_{i:02d}.png")
EOF

    python3 /tmp/gen_frames.py

    # Create the video
    ffmpeg -framerate 1 -i /tmp/frames/frame_%02d.png -c:v libx264 -r 1 -pix_fmt yuv420p /app/telemetry.mp4

    # Cleanup
    rm -rf /tmp/frames /tmp/gen_frames.py

    # Setup user and workspace
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/workspace
    chmod -R 777 /home/user

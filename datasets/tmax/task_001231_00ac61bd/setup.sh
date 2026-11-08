#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg parallel imagemagick curl
    pip3 install pytest Pillow scipy flask requests

    mkdir -p /app/frames

    cat << 'EOF' > /tmp/gen_video.py
import math
import os
from PIL import Image, ImageDraw

K = 0.8
D0 = 0.05
r = 0.15
for t in range(50):
    D = K / (1 + ((K - D0) / D0) * math.exp(-r * t))
    area = D * 40000
    rad = math.sqrt(area / math.pi)
    img = Image.new('L', (200, 200), 0)
    draw = ImageDraw.Draw(img)
    draw.ellipse([100 - rad, 100 - rad, 100 + rad, 100 + rad], fill=255)
    img.save(f'/app/frames/frame_{t:03d}.png')
EOF

    python3 /tmp/gen_video.py
    ffmpeg -framerate 1 -i /app/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/bacteria_growth.mp4
    rm -rf /app/frames /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

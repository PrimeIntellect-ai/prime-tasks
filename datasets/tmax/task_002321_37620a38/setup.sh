#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make ffmpeg
    pip3 install pytest Pillow

    mkdir -p /app/frames

    python3 -c "
from PIL import Image
import os
os.makedirs('/app/frames', exist_ok=True)
colors = [(5,12,10), (12,50,20), (5,50,50), (12,8,5)]
for i in range(1, 51):
    c = colors[i-1] if i <= len(colors) else (255,255,255)
    img = Image.new('RGB', (64, 64), color=c)
    img.save(f'/app/frames/frame{i:02d}.png')
"

    ffmpeg -framerate 1 -i /app/frames/frame%02d.png -c:v libx264 -pix_fmt yuv444p /app/backup_topology.mp4
    rm -rf /app/frames

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++ python3-pil
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    echo -e "BACKUP_JOB=alpha\nTARGET_IP=10.0.0.15\nSTATUS=active" > /app/corpus/clean/manifest_1.txt
    echo -e "BACKUP_JOB=beta\nTARGET_IP=10.0.0.250\nSTATUS=active" > /app/corpus/clean/manifest_2.txt

    echo -e "BACKUP_JOB=gamma\nTARGET_IP=192.168.1.50\nSTATUS=active" > /app/corpus/evil/manifest_1.txt
    echo -e "BACKUP_JOB=delta\nTARGET_IP=10.0.1.15\nSTATUS=active" > /app/corpus/evil/manifest_2.txt
    echo -e "BACKUP_JOB=epsilon\nTARGET_IP=8.8.8.8\nSTATUS=active" > /app/corpus/evil/manifest_3.txt

    # Generate the incident video with a lossless codec to preserve the exact RGB pixel value
    cat << 'EOF' > /tmp/gen_video.py
from PIL import Image
import subprocess
import os

os.makedirs('/tmp/frames', exist_ok=True)
for i in range(20):
    img = Image.new('RGB', (200, 200), color='black')
    if i == 14:
        img.putpixel((100, 100), (255, 255, 255))
    img.save(f'/tmp/frames/frame_{i:02d}.png')

subprocess.run([
    'ffmpeg', '-y', '-framerate', '1', 
    '-i', '/tmp/frames/frame_%02d.png', 
    '-c:v', 'libx264rgb', '-crf', '0', 
    '/app/incident.mp4'
], check=True)
EOF

    python3 /tmp/gen_video.py
    rm -rf /tmp/frames /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

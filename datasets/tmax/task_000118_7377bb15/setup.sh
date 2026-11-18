#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg p7zip-full
    pip3 install pytest pillow

    mkdir -p /app/corpus/clean /app/corpus/evil /app/frames

    # Generate video
    cat << 'EOF' > /app/gen_video.py
from PIL import Image
import os
import subprocess

for i in range(300):
    img = Image.new('RGB', (640, 480), color=(0, 0, 0))
    if i < 42:
        img.putpixel((320, 240), (255, 0, 0))
    img.save(f'/app/frames/frame_{i:03d}.png')

subprocess.run(['ffmpeg', '-y', '-framerate', '30', '-i', '/app/frames/frame_%03d.png', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '/app/incident_record.mp4'], check=True)
EOF
    python3 /app/gen_video.py
    rm -rf /app/frames /app/gen_video.py

    # Generate archives
    mkdir -p /app/dummy_clean /app/dummy_evil
    echo "clean data" > /app/dummy_clean/data.txt
    echo "evil data" > /app/dummy_evil/data.txt
    ln -s /etc/shadow /app/dummy_evil/bad_link

    for i in $(seq 1 20); do
        7z a -tzip -p42 /app/corpus/clean/clean_${i}.zip /app/dummy_clean/* > /dev/null
        7z a -tzip -p42 /app/corpus/evil/evil_${i}.zip /app/dummy_evil/* > /dev/null
    done

    rm -rf /app/dummy_clean /app/dummy_evil

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

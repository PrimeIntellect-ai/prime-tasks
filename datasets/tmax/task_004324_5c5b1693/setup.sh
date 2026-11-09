#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg python3-pil
    pip3 install pytest

    mkdir -p /app/clean /app/evil /tmp/frames

    cat << 'EOF' > /tmp/setup.py
import os
import zlib
from PIL import Image

# Generate video frames
bits = [0, 1, 1, 0, 1, 1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 0, 1, 1, 0]
for i, b in enumerate(bits):
    color = (255, 255, 255) if b else (0, 0, 0)
    img = Image.new('RGB', (100, 100), color)
    img.save(f"/tmp/frames/frame_{i:02d}.png")

# Generate video
os.system("ffmpeg -y -framerate 1 -i /tmp/frames/frame_%02d.png -c:v libx264 -r 1 -pix_fmt yuv420p /app/key_transmission.mp4")

key = 0xB2A5

def get_token(username):
    crc = zlib.crc32(username.encode('utf-8')) & 0xFFFF
    return f"{crc ^ key:04x}"

# Clean corpus
with open('/app/clean/file1.txt', 'w') as f:
    f.write(f"admin:{get_token('admin')}\n")
    f.write(f"user1:{get_token('user1')}\n")

with open('/app/clean/file2.txt', 'w') as f:
    f.write(f"test:{get_token('test')}\n")

# Evil corpus
with open('/app/evil/file1.txt', 'w') as f:
    f.write(f"admin:{get_token('admin')}\n")
    f.write(f"user1:0000\n")

with open('/app/evil/file2.txt', 'w') as f:
    f.write(f"test:1234\n")
EOF

    python3 /tmp/setup.py
    rm -rf /tmp/frames /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

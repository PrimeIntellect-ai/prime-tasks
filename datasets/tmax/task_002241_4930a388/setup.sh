#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++ make cmake nlohmann-json3-dev jq
    pip3 install pytest pillow

    mkdir -p /app/corpora/clean /app/corpora/evil

    cat << 'EOF' > /app/corpora/clean/safe1.json
{"depends_on": "concat(parent(file(\"src/config.json\")), \"/settings.json\")"}
EOF

    cat << 'EOF' > /app/corpora/clean/safe2.json
{"depends_on": "file(\"docs/readme.md\")"}
EOF

    cat << 'EOF' > /app/corpora/evil/attack1.json
{"depends_on": "concat(parent(file(\"src/config\")), \"/../../etc/shadow\")"}
EOF

    cat << 'EOF' > /app/corpora/evil/attack2.json
{"depends_on": "file(\"../hidden_secrets.txt\")"}
EOF

    cat << 'EOF' > /tmp/gen_video.py
from PIL import Image, ImageDraw
import subprocess
import os

os.makedirs('/tmp/frames', exist_ok=True)
for i in range(1, 301):
    img = Image.new('RGB', (100, 100), color='black')
    if i <= 42:
        draw = ImageDraw.Draw(img)
        draw.rectangle([0, 0, 9, 9], fill=(0, 255, 0))
    img.save(f'/tmp/frames/frame_{i:03d}.png')

subprocess.run(['ffmpeg', '-y', '-framerate', '30', '-i', '/tmp/frames/frame_%03d.png', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '/app/file_events.mp4'], check=True)
EOF

    python3 /tmp/gen_video.py
    rm -rf /tmp/frames /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

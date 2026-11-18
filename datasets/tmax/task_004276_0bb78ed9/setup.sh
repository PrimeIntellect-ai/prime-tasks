#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++
    pip3 install pytest Pillow

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate video
    cat << 'EOF' > /tmp/gen_video.py
import os
from PIL import Image

os.makedirs('/tmp/frames', exist_ok=True)
white_frames = [5, 12, 19, 34, 51]
for i in range(60):
    img = Image.new('RGB', (100, 100), color='black')
    if i in white_frames:
        for x in range(10):
            for y in range(10):
                img.putpixel((x, y), (255, 255, 255))
    img.save(f'/tmp/frames/frame_{i:03d}.png')
EOF
    python3 /tmp/gen_video.py
    ffmpeg -framerate 1 -i /tmp/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/audit_log.mp4
    rm -rf /tmp/frames /tmp/gen_video.py

    # Create dummy files
    echo "NodeA\tNodeB" > /app/config_dag.tsv
    echo "template_content" > /app/template.conf

    # Create corpus files
    echo "valid config" > /app/corpus/clean/clean1.txt
    echo "another valid config with \"$VAR\"" > /app/corpus/clean/clean2.txt

    echo -e "invalid \u202E config" > /app/corpus/evil/evil1.txt
    echo "invalid config with unescaped $VAR" > /app/corpus/evil/evil2.txt
    echo "invalid config with unescaped \`ls\`" > /app/corpus/evil/evil3.txt
    echo "invalid config with unescaped | pipe" > /app/corpus/evil/evil4.txt
    echo "invalid config with unescaped ; semi" > /app/corpus/evil/evil5.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

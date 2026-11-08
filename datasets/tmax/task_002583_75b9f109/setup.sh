#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr
    pip3 install pytest Pillow pytesseract

    mkdir -p /app/traces
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Generate Video
    mkdir -p /tmp/frames
    cat << 'EOF' > /tmp/gen_vid.py
import os
from PIL import Image, ImageDraw, ImageFont

for i in range(60):
    img = Image.new('RGB', (320, 240), color='green')
    if i in [12, 25, 48]:
        img = Image.new('RGB', (320, 240), color='red')
        d = ImageDraw.Draw(img)
        text = ""
        if i == 12: text = "FAILURE: JOB_1012"
        elif i == 25: text = "FAILURE: JOB_1045"
        elif i == 48: text = "FAILURE: JOB_1099"
        d.text((10, 100), text, fill=(255,255,255))
    img.save(f"/tmp/frames/frame_{i:03d}.png")
EOF
    python3 /tmp/gen_vid.py
    ffmpeg -y -framerate 1 -i /tmp/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/incident_monitor.mp4
    rm -rf /tmp/frames /tmp/gen_vid.py

    # Generate Traces
    cat << 'EOF' > /tmp/gen_traces.py
import os

for i in range(1000, 1101):
    d = f"/app/traces/job_{i}"
    os.makedirs(d, exist_ok=True)
    with open(f"{d}/strace.log", "w") as f:
        if i == 1012:
            f.write('execve("/bin/sh", ["sh", "-c", "process my video.mp4"], 0x7ffd... /* 50 vars */) = -1 ENOENT\n')
        elif i == 1045:
            f.write('execve("/bin/sh", ["sh", "-c", "process video;rm -rf /.mp4"], 0x7ffd... /* 50 vars */) = 0\n')
        elif i == 1099:
            f.write('execve("/bin/sh", ["sh", "-c", "process $(whoami).mp4"], 0x7ffd... /* 50 vars */) = 0\n')
        else:
            f.write(f'execve("/bin/sh", ["sh", "-c", "process video_{i}.mp4"], 0x7ffd... /* 50 vars */) = 0\n')
EOF
    python3 /tmp/gen_traces.py
    rm /tmp/gen_traces.py

    # Generate Corpora
    echo "my video.mp4" > /app/corpora/evil/1.txt
    echo "video;rm -rf /.mp4" > /app/corpora/evil/2.txt
    echo "vid'eo.mp4" > /app/corpora/evil/3.txt
    echo "vid\"eo.mp4" > /app/corpora/evil/4.txt
    echo '$(whoami).mp4' > /app/corpora/evil/5.txt
    echo "video&.mp4" > /app/corpora/evil/6.txt
    echo -e "test\n.mp4" > /app/corpora/evil/7.txt

    echo "video.mp4" > /app/corpora/clean/1.txt
    echo "my_video-123.mp4" > /app/corpora/clean/2.txt
    echo "/mnt/data/video.mp4" > /app/corpora/clean/3.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

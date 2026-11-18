#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr
    pip3 install pytest Pillow pytesseract opencv-python-headless

    mkdir -p /app/tests/corpus/evil /app/tests/corpus/clean

    # Generate video
    cat << 'EOF' > /tmp/gen_video.py
import os
import subprocess
from PIL import Image, ImageDraw

configs = [
    ("sshd_config", "PermitRootLogin yes\nPort 22\n"),
    ("nginx.conf", "server {\n  listen 80;\n  server_name localhost;\n}\n"),
    ("database.yml", "production:\n  adapter: postgresql\n  host: 203.0.113.5\n"),
    ("app_config.json", '{\n  "app_name": "myapp",\n  "version": "1.0"\n}\n'),
    ("sysctl.conf", "net.ipv4.ip_forward = 1\nListenAddress 0.0.0.0\n")
]

os.makedirs("/tmp/frames", exist_ok=True)
frame_idx = 0
for name, content in configs:
    text = f"File: {name}\n\n{content}"
    for _ in range(30):
        img = Image.new('RGB', (800, 600), color=(0, 0, 0))
        d = ImageDraw.Draw(img)
        d.text((10, 10), text, fill=(255, 255, 255))
        img.save(f"/tmp/frames/frame_{frame_idx:04d}.png")
        frame_idx += 1

subprocess.run(["ffmpeg", "-y", "-framerate", "30", "-i", "/tmp/frames/frame_%04d.png", "-c:v", "libx264", "-pix_fmt", "yuv420p", "/app/config_session.mp4"], check=True)
EOF
    python3 /tmp/gen_video.py
    rm -rf /tmp/frames /tmp/gen_video.py

    # Generate corpus
    cat << 'EOF' > /tmp/gen_corpus.py
import os

evil_dir = "/app/tests/corpus/evil/"
clean_dir = "/app/tests/corpus/clean/"

evil_contents = [
    "PermitRootLogin yes\n",
    "PasswordAuthentication yes\n",
    "ListenAddress 0.0.0.0\n",
    "host: 8.8.8.8\n",
    "server 172.16.0.1\n"
]

clean_contents = [
    "PermitRootLogin no\n",
    "PasswordAuthentication no\n",
    "ListenAddress 127.0.0.1\n",
    "host: 10.1.2.3\n",
    "server 192.168.1.1\n"
]

for i in range(50):
    with open(os.path.join(evil_dir, f"evil_{i}.conf"), "w") as f:
        f.write(evil_contents[i % len(evil_contents)])
    with open(os.path.join(clean_dir, f"clean_{i}.conf"), "w") as f:
        f.write(clean_contents[i % len(clean_contents)])
EOF
    python3 /tmp/gen_corpus.py
    rm /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        zbar-tools \
        qrencode

    pip3 install pytest qrcode pillow

    mkdir -p /app/corpus/clean /app/corpus/evil /tmp/frames

    cat << 'EOF' > /tmp/setup.py
import os
import zlib
import qrcode
from PIL import Image
import subprocess

# Generate video frames
for i in range(300):
    text = ""
    if i == 30: text = "CRC_PO"
    elif i == 150: text = "LYNOMIAL=0xEDB88320;"
    elif i == 270: text = "TEST_MODE=STRICT"

    if text:
        img = qrcode.make(text).resize((400, 400)).convert('RGB')
        img.save(f"/tmp/frames/frame_{i:03d}.png")
    else:
        img = Image.new('RGB', (400, 400), color='black')
        img.save(f"/tmp/frames/frame_{i:03d}.png")

subprocess.run(["ffmpeg", "-y", "-framerate", "30", "-i", "/tmp/frames/frame_%03d.png", "-c:v", "libx264", "-pix_fmt", "yuv420p", "/app/ci_telemetry.mp4"], check=True)

# Generate corpus
def write_file(path, content, valid_crc=True):
    crc = zlib.crc32(content.encode('utf-8')) & 0xFFFFFFFF
    if not valid_crc:
        crc = (crc + 1) & 0xFFFFFFFF
    with open(path, 'w') as f:
        f.write(f"# CHECKSUM: {crc:08x}\n")
        f.write(content)

for i in range(1, 6):
    d = f"/app/corpus/clean/proj_{i}"
    os.makedirs(d, exist_ok=True)
    open(f"{d}/requirements.txt", 'w').write("")
    write_file(f"{d}/a.py", "def a(): pass\n")
    write_file(f"{d}/b.py", "import a\ndef b(): pass\n")
    write_file(f"{d}/c.py", "import b\ndef c(): pass\n")

for i in range(1, 6):
    d = f"/app/corpus/evil/evil_{i}"
    os.makedirs(d, exist_ok=True)
    open(f"{d}/requirements.txt", 'w').write("")
    if i in [1, 2]:
        write_file(f"{d}/a.py", "def a(): pass\n", valid_crc=False)
        write_file(f"{d}/b.py", "def b(): pass\n")
    elif i in [3, 4]:
        write_file(f"{d}/a.py", "import b\ndef a(): pass\n")
        write_file(f"{d}/b.py", "import a\ndef b(): pass\n")
    elif i == 5:
        write_file(f"{d}/a.py", "def a(): pass\n")
        open(f"{d}/requirements.txt", 'w').write("nonexistent-package-xyz-12345==99.99.99\n")
EOF

    python3 /tmp/setup.py
    rm -rf /tmp/frames /tmp/setup.py

    chmod -R 755 /app/corpus
    chmod 644 /app/ci_telemetry.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

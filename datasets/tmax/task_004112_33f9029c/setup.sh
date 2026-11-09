#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import struct
import os
import subprocess

# 1. Create the encrypted archive
files = [
    ("log1.txt", b"data1"),
    ("config/settings.ini", b"data2"),
    ("users.db", b"data3"),
    ("../etc/passwd", b"malicious1"),
    ("../../../shadow", b"malicious2"),
    ("/root/.bashrc", b"malicious3")
]

archive = b""
for path, data in files:
    path_b = path.encode('ascii')
    archive += struct.pack("<H", len(path_b))
    archive += path_b
    archive += struct.pack("<I", len(data))
    archive += data

key = b"s3cr3tK3y"
encrypted = bytearray()
for i in range(len(archive)):
    encrypted.append(archive[i] ^ key[i % len(key)])

with open("/home/user/corrupt_backup.wal", "wb") as f:
    f.write(encrypted)

# 2. Create the video
bits = []
for b in key:
    for i in range(7, -1, -1):
        bits.append((b >> i) & 1)

os.makedirs("/tmp/frames", exist_ok=True)
for i, bit in enumerate(bits):
    color = 255 if bit else 0
    with open(f"/tmp/frames/frame_{i:03d}.pgm", "w") as f:
        f.write(f"P2\n10 10\n255\n")
        for _ in range(100):
            f.write(f"{color}\n")

subprocess.run([
    "ffmpeg", "-y", "-framerate", "10", 
    "-i", "/tmp/frames/frame_%03d.pgm", 
    "-c:v", "libx264", "-pix_fmt", "yuv420p", 
    "/app/incident.mp4"
], check=True)
EOF

    python3 /tmp/setup.py
    rm -rf /tmp/setup.py /tmp/frames

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

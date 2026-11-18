#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest opencv-python-headless numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import zlib
import cv2
import numpy as np

os.makedirs('/home/user/artifacts', exist_ok=True)
os.makedirs('/app', exist_ok=True)

key_bytes = b'\xaa\x55\x12\x34\xde\xad\xbe\xef\x00\xff\x42\x24\x99\x66\x33\xcc'

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/key_feed.mp4', fourcc, 30.0, (64, 64), isColor=False)

for byte in key_bytes:
    for i in range(7, -1, -1):
        bit = (byte >> i) & 1
        color = 255 if bit == 1 else 0
        frame = np.full((64, 64), color, dtype=np.uint8)
        out.write(frame)
out.release()

def encrypt(data, key):
    compressed = zlib.compress(data)
    return bytes([b ^ key[i % len(key)] for i, b in enumerate(compressed)])

alpha_data = b"; BEGIN GCODE\nG1 X10 Y20\nM104 S200\n"
with open('/home/user/artifacts/alpha.gcode.enc', 'wb') as f:
    f.write(encrypt(alpha_data, key_bytes))

beta_data = b"; BEGIN GCODE\nG28\nG1 Z10\n"
with open('/home/user/artifacts/beta.gcode.enc', 'wb') as f:
    f.write(encrypt(beta_data, key_bytes))

with open('/home/user/artifacts/gamma.gcode.enc', 'wb') as f:
    f.write(os.urandom(50))

delta_data = b"; WRONG HEADER\nG1 X0 Y0\n"
with open('/home/user/artifacts/delta.gcode.enc', 'wb') as f:
    f.write(encrypt(delta_data, key_bytes))
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chown -R user:user /home/user/artifacts
    chmod -R 777 /home/user

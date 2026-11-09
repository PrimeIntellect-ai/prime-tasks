#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg sqlite3
pip3 install pytest flask fastapi uvicorn networkx opencv-python-headless numpy

mkdir -p /app
mkdir -p /tmp/frames

# Generate video frames
python3 -c "
import os
data = '[{\"source\":\"A\",\"target\":\"B\",\"weight\":5},{\"source\":\"A\",\"target\":\"C\",\"weight\":2},{\"source\":\"B\",\"target\":\"C\",\"weight\":2},{\"source\":\"C\",\"target\":\"D\",\"weight\":4},{\"source\":\"D\",\"target\":\"E\",\"weight\":3},{\"source\":\"C\",\"target\":\"F\",\"weight\":10}]'
bits = ''.join(f'{ord(c):08b}' for c in data)
for i, bit in enumerate(bits):
    val = b'\xff' if bit == '1' else b'\x00'
    with open(f'/tmp/frames/frame_{i:04d}.pgm', 'wb') as f:
        f.write(f'P5\n100 100\n255\n'.encode())
        f.write(val * 10000)
"

# Encode frames into a lossless video
ffmpeg -framerate 30 -i /tmp/frames/frame_%04d.pgm -c:v libx264 -crf 0 /app/dataset_transmission.mp4
rm -rf /tmp/frames

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install system dependencies for the task and setup script
    apt-get install -y libglib2.0-0 ffmpeg gawk sed findutils gcc libc6-dev libmicrohttpd-dev unzip tar gzip curl

    # Install Python dependencies for the setup script
    pip3 install opencv-python-headless numpy

    # Create directories
    mkdir -p /app
    mkdir -p /tmp/gen_configs

    # Create setup script
    cat << 'EOF' > /tmp/setup.py
import os
import cv2
import numpy as np
import tarfile
import zipfile

os.makedirs('/app', exist_ok=True)

# 1. Generate Video
key = "KEY_B5x9_P!q2M"
bits = ''.join([f"{ord(c):08b}" for c in key])

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/system_monitor.mp4', fourcc, 1.0, (320, 240))

for bit in bits:
    frame = np.zeros((240, 320, 3), dtype=np.uint8)
    if bit == '1':
        frame[0:10, 0:10] = (255, 255, 255)
    out.write(frame)
out.release()

# 2. Generate Nested Archive
os.makedirs('/tmp/gen_configs', exist_ok=True)
with open('/tmp/gen_configs/app1.conf', 'w') as f:
    f.write("server_ip=192.168.1.50\nmode=legacy\nthreads=4\n")
with open('/tmp/gen_configs/db.conf', 'w') as f:
    f.write("server_ip=192.168.1.101\nmode=legacy\ncache=256M\n")

# Zip
with zipfile.ZipFile('/tmp/gen_configs/inner.zip', 'w') as z:
    z.write('/tmp/gen_configs/app1.conf', 'app1.conf')
    z.write('/tmp/gen_configs/db.conf', 'db.conf')

# Tar inside Tar
with tarfile.open('/tmp/gen_configs/inner.tar.gz', 'w:gz') as t:
    t.add('/tmp/gen_configs/inner.zip', arcname='inner.zip')

with tarfile.open('/app/legacy_configs.tar', 'w') as t:
    t.add('/tmp/gen_configs/inner.tar.gz', arcname='inner.tar.gz')
EOF

    # Run setup script
    python3 /tmp/setup.py

    # Cleanup
    rm -rf /tmp/setup.py /tmp/gen_configs

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

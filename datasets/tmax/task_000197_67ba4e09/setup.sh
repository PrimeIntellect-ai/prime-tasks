#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends python3 python3-pip ffmpeg
    pip3 install pytest Pillow

    mkdir -p /app/staging/dataset_alpha
    mkdir -p /app/staging/dataset_gamma
    mkdir -p /app/staging/dataset_zeta
    mkdir -p /app/staging/dataset_beta

    touch /app/staging/dataset_alpha/file1.dat
    touch /app/staging/dataset_alpha/file2.dat
    touch /app/staging/dataset_gamma/file3.dat
    touch /app/staging/dataset_zeta/file4.dat
    touch /app/staging/dataset_zeta/file5.dat
    touch /app/staging/dataset_beta/file6.dat

    touch -d "10 days ago" /app/staging/dataset_alpha/old.dat

    cat << 'EOF' > /app/backup_runs.log
[Timestamp]
Target: /app/staging/dataset_alpha
Owner: username
Status: FAILED
Bytes: 1024
--
[Timestamp]
Target: /app/staging/dataset_beta
Owner: username
Status: SUCCESS
Bytes: 2048
--
[Timestamp]
Target: /app/staging/dataset_gamma
Owner: username
Status: FAILED
Bytes: 1024
--
[Timestamp]
Target: /app/staging/dataset_zeta
Owner: username
Status: FAILED
Bytes: 1024
--
EOF

    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    cat << 'EOF' > /tmp/make_video.py
from PIL import Image
import os

os.makedirs('/tmp/frames', exist_ok=True)
for i in range(30):
    if i < 14:
        color = (255, 0, 0)
    else:
        color = (0, 0, 0)
    img = Image.new('RGB', (100, 100), color)
    img.save(f'/tmp/frames/frame_{i:03d}.png')
EOF
    python3 /tmp/make_video.py
    ffmpeg -framerate 10 -i /tmp/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/dashboard_alert.mp4
    rm -rf /tmp/frames /tmp/make_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libzbar0
    pip3 install --default-timeout=100 pytest opencv-python-headless pyzbar flask fastapi uvicorn python-barcode Pillow numpy

    mkdir -p /app

    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np
import barcode
from barcode.writer import ImageWriter
import os

edges = [
    "ProtA-ProtB-50",
    "ProtB-ProtC-80",
    "ProtA-ProtD-90",
    "ProtC-ProtHub-60",
    "ProtD-ProtHub-40",
    "ProtX-ProtY-10",
    "ProtY-ProtA-20",
    "ProtB-ProtHub-30",
    "ProtZ-ProtHub-99",
    "ProtA-ProtZ-5"
]

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/experiment_run.mp4', fourcc, 1.0, (640, 480))

for edge in edges:
    code128 = barcode.Code128(edge, writer=ImageWriter())
    code128.save('/tmp/temp_barcode')
    img = cv2.imread('/tmp/temp_barcode.png')
    img = cv2.resize(img, (640, 480))
    out.write(img)

out.release()
EOF

    python3 /tmp/generate_video.py
    rm /tmp/generate_video.py /tmp/temp_barcode.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

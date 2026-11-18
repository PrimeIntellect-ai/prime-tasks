#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc tar
    pip3 install pytest

    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=5:size=640x480:rate=25 -c:v libx264 -pix_fmt yuv420p /app/experiment.mp4

    python3 -c '
import struct
import math

with open("/app/metadata.bin", "wb") as f:
    # Header: "DATA" (4 bytes), Version=1 (4 bytes), Count=100 (8 bytes)
    f.write(struct.pack("<4s I Q", b"DATA", 1, 100))
    for i in range(1, 101):
        # Event code: i % 5
        # Sensor value: float(i * 3.14)
        f.write(struct.pack("<I I d", i, i % 5, float(i * 3.14)))
'

    chmod 644 /app/metadata.bin
    chmod 644 /app/experiment.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

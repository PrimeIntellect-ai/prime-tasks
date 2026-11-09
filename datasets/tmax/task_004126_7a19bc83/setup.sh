#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app
    # Generate a 20-second dummy video to act as the dashcam footage
    ffmpeg -f lavfi -i testsrc=duration=20:size=640x480:rate=30 -pix_fmt yuv420p /app/dashcam.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg nginx gcc gawk openssl curl
    pip3 install pytest

    mkdir -p /app/data
    # Generate a 10-second 30fps test video
    ffmpeg -y -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -c:v libx264 /app/data/surveillance.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

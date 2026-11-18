#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y ffmpeg gcc netcat-openbsd

    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=2:size=128x128:rate=10 -c:v libx264 -pix_fmt yuv420p /app/input.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

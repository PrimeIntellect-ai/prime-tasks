#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++ curl
    pip3 install pytest

    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=2:size=320x240:rate=10 -c:v libx264 -bf 2 -g 10 /app/video.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

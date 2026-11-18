#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest requests

    mkdir -p /app
    ffmpeg -f lavfi -i "testsrc=duration=2:size=320x240:rate=10" -c:v libx264 -pix_fmt yuv420p /app/test_feed.mp4 -y

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

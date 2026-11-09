#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang
    pip3 install pytest

    # Create /app directory and generate a dummy video file
    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=5:size=320x240:rate=10 -c:v libx264 -pix_fmt yuv420p /app/data_video.mp4

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

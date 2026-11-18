#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg build-essential
    pip3 install pytest

    mkdir -p /app
    # Generate a highly compressible static video
    ffmpeg -f lavfi -i color=c=gray:s=640x480:r=1 -t 30 -c:v libx264 /app/cctv.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc libc6-dev libjpeg-dev make
    pip3 install pytest numpy scipy imageio

    mkdir -p /app
    # Generate a 10-second test video
    ffmpeg -y -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -pix_fmt yuv420p /app/video.mp4

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/frames
    chmod -R 777 /home/user
    chmod -R 777 /app

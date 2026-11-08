#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app
    # Generate a 15-second video (450 frames at 30fps) with a massive entropy spike exactly at frame 402
    ffmpeg -y -f lavfi -i color=c=black:s=640x480:r=30 -f lavfi -i mandelbrot=s=640x480 \
        -filter_complex "[0:v][1:v]overlay=enable='eq(n,402)'" \
        -t 15 -c:v libx264 -crf 18 /app/attack_capture.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

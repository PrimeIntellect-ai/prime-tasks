#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc make netcat
    pip3 install pytest numpy

    mkdir -p /app
    # Generate a dummy surveillance video
    ffmpeg -y -f lavfi -i testsrc=duration=15:size=640x480:rate=30 -c:v libx264 -pix_fmt yuv420p /app/surveillance.mp4

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/frames
    mkdir -p /home/user/etl

    chmod -R 777 /home/user
    chmod -R 777 /app

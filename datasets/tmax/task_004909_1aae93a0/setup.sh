#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang ffmpeg
    pip3 install pytest

    mkdir -p /app/configs/subdir
    echo "server=nginx" > /app/configs/app.conf
    echo "db=postgres" > /app/configs/subdir/db.conf
    ln -s /app/configs /app/configs/subdir/loop

    # Generate a dummy surveillance video (5 seconds, 30 fps)
    ffmpeg -f lavfi -i testsrc=duration=5:size=320x240:rate=30 -c:v libx264 -pix_fmt yuv420p /app/surveillance.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

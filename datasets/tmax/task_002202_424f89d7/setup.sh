#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest Pillow flask requests

    mkdir -p /app
    cd /app

    # Generate test video
    ffmpeg -f lavfi -i color=c=black:s=100x100 -vframes 1 frame_01.png
    ffmpeg -f lavfi -i color=c=black:s=100x100 -vframes 1 frame_02.png
    ffmpeg -f lavfi -i color=c=gray:s=100x100 -vframes 1 frame_03.png
    ffmpeg -f lavfi -i color=c=white:s=100x100 -vframes 1 frame_04.png
    ffmpeg -f lavfi -i color=c=white:s=100x100 -vframes 1 frame_05.png
    ffmpeg -framerate 1 -i frame_%02d.png -c:v libx264 -pix_fmt yuv420p /app/traffic_monitor.mp4

    rm frame_*.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

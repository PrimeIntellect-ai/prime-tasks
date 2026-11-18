#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg cargo rustc
    pip3 install pytest pandas numpy

    mkdir -p /app
    ffmpeg -y -f lavfi -i "color=c=black:s=64x64:d=10,geq=lum='255*sin(T)'" -r 24 /app/sensor_video.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

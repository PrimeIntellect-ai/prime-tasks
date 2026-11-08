#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang curl
    pip3 install pytest

    mkdir -p /app
    ffmpeg -f lavfi -i "nullsrc=s=320x240:d=10:r=1" -vf "noise=alls=100:allf=t+u" -c:v libx264 -y /app/traffic.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

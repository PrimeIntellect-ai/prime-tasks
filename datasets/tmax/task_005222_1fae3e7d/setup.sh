#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang-go
    pip3 install pytest

    mkdir -p /app
    # Generate a video with a black frame between 12.5s and 13.0s
    ffmpeg -y -f lavfi -i "color=c=white:s=320x240:d=12.5" \
           -f lavfi -i "color=c=black:s=320x240:d=0.5" \
           -f lavfi -i "color=c=white:s=320x240:d=2.0" \
           -filter_complex "[0:v][1:v][2:v]concat=n=3:v=1:a=0[outv]" \
           -map "[outv]" /app/presentation.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

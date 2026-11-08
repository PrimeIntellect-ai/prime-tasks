#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        gcc \
        supervisor \
        logrotate \
        acl \
        locales \
        tzdata

    pip3 install pytest

    # Generate required locale
    locale-gen de_DE.UTF-8

    # Create user
    useradd -m -s /bin/bash user || true

    # Create app directory and generate the video fixture
    mkdir -p /app
    # Generate a 10-second 30fps video where all frames are white except frame 142 (0-indexed) which is black
    ffmpeg -f lavfi -i color=c=white:s=320x240:r=30 -vf "drawbox=x=0:y=0:w=320:h=240:color=black:t=fill:enable='eq(n\,142)'" -frames:v 300 -c:v libx264 -pix_fmt yuv420p /app/camera_feed.mp4

    # Ensure home directory permissions
    chmod -R 777 /home/user

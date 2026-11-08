#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install necessary system packages
    apt-get install -y ffmpeg fonts-liberation openssl

    # Create app directory
    mkdir -p /app

    # Generate the video with the hidden token between frames 150 and 160
    # 10 seconds at 30fps = 300 frames.
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=10:r=30 \
        -vf "drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf:text='Session token\: c3VwZXJfc2VjcmV0X2FkbWluX3Rva2VuXzEyMw==':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(n,150,160)'" \
        -c:v libx264 -pix_fmt yuv420p /app/admin_session.mp4

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/certs
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y qrencode ffmpeg zbar-tools socat bc curl

    # Generate video for the task
    mkdir -p /tmp/frames
    mkdir -p /app

    qrencode -s 10 -o /tmp/frames/frame0.png "15 + 10"
    qrencode -s 10 -o /tmp/frames/frame1.png "8 * 4"
    qrencode -s 10 -o /tmp/frames/frame2.png "100 / 2"
    qrencode -s 10 -o /tmp/frames/frame3.png "cat /etc/passwd"
    qrencode -s 10 -o /tmp/frames/frame4.png "99 - 9"

    # Scale to ensure even dimensions for libx264
    ffmpeg -framerate 1 -i /tmp/frames/frame%d.png -vf "scale=320:320" -c:v libx264 -r 30 -pix_fmt yuv420p /app/auth_events.mp4
    chmod 644 /app/auth_events.mp4

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

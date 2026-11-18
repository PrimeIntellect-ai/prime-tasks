#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go ffmpeg imagemagick cron logrotate
    pip3 install pytest

    # Create the app directory
    mkdir -p /app/frames

    # Generate 7 red frames and 93 black frames
    for i in $(seq 1 100); do
        num=$(printf "%03d" $i)
        if [ "$i" -le 7 ]; then
            convert -size 100x100 xc:red /app/frames/frame_$num.jpg
        else
            convert -size 100x100 xc:black /app/frames/frame_$num.jpg
        fi
    done

    # Encode to mp4
    ffmpeg -framerate 10 -i /app/frames/frame_%03d.jpg -c:v libx264 -pix_fmt yuv420p /app/dashboard_capture.mp4

    # Cleanup frames
    rm -rf /app/frames

    # Create user
    useradd -m -s /bin/bash user || true

    # Prepare user directory for the task
    mkdir -p /home/user/obs
    chmod -R 777 /home/user

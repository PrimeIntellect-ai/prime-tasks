#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install dependencies for the task
    apt-get install -y ffmpeg golang imagemagick

    # Create the app directory
    mkdir -p /app
    mkdir -p /tmp/frames

    # Generate 60 images
    for i in $(seq 1 60); do
        idx=$(printf "%04d" $i)
        if [ "$i" -eq 12 ] || [ "$i" -eq 13 ] || [ "$i" -eq 14 ] || [ "$i" -eq 45 ]; then
            convert -size 640x480 xc:black /tmp/frames/frame_$idx.jpg
        else
            # Create a simple colored image (different for each to have different histograms)
            convert -size 640x480 xc:"rgb($((i*4)),$((i*2)),$((i*3)))" /tmp/frames/frame_$idx.jpg
        fi
    done

    # Encode into a 60-second 30fps video
    ffmpeg -framerate 1 -i /tmp/frames/frame_%04d.jpg -c:v libx264 -r 30 -pix_fmt yuv420p /app/factory_feed.mp4

    # Cleanup temp frames
    rm -rf /tmp/frames

    # Create the user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

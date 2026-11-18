#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app/media_assets/logs
    mkdir -p /app/media_assets/documents

    echo "system boot" > /app/media_assets/logs/system.log
    echo "important data" > /app/media_assets/documents/data.txt

    # Create the symlink loop
    ln -s /app/media_assets/logs /app/media_assets/logs/infinite

    # Create a valid symlink to a file outside the directory
    echo "external secret" > /tmp/external.txt
    ln -s /tmp/external.txt /app/media_assets/documents/external_link.txt

    # Generate the surveillance video
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -c:v libx264 /app/media_assets/surveillance.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

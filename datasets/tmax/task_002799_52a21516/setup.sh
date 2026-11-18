#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo podman curl ffmpeg e2fsprogs
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/evil /app/corpus/clean
    mkdir -p /tmp/evidence_dir

    # Generate video with exactly 17 pure red frames
    ffmpeg -f lavfi -i "color=black:s=100x100:r=10" -vframes 10 /tmp/black.mp4
    ffmpeg -f lavfi -i "color=red:s=100x100:r=10" -vframes 17 /tmp/red.mp4
    echo "file '/tmp/black.mp4'" > /tmp/list.txt
    echo "file '/tmp/red.mp4'" >> /tmp/list.txt
    ffmpeg -f concat -safe 0 -i /tmp/list.txt -c copy /tmp/evidence_dir/network_status.mp4

    # Create ext4 image
    dd if=/dev/zero of=/app/evidence.img bs=1M count=20
    mkfs.ext4 -d /tmp/evidence_dir /app/evidence.img

    # Clean up temp files
    rm -f /tmp/black.mp4 /tmp/red.mp4 /tmp/list.txt
    rm -rf /tmp/evidence_dir

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    # Create mount point for the task
    mkdir -p /mnt/evidence

    chmod -R 777 /app
    chmod -R 777 /home/user

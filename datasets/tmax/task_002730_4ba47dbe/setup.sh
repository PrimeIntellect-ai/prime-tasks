#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg fonts-dejavu-core rustc cargo
    pip3 install pytest

    mkdir -p /app/bloated_dir/logs
    mkdir -p /app/bloated_dir/configs
    mkdir -p /app/bloated_dir/cache

    # Create dummy duplicate files (1000 identical 1MB files)
    dd if=/dev/urandom of=/tmp/base_file.dat bs=1M count=1
    seq 1 1000 | xargs -I {} cp /tmp/base_file.dat "/app/bloated_dir/logs/log_{}.dat"

    # Create a few different files
    echo "config1" > /app/bloated_dir/configs/c1.cfg
    echo "config2" > /app/bloated_dir/configs/c2.cfg

    # Create malicious symlinks (zip slip simulation)
    ln -s /etc/passwd /app/bloated_dir/configs/passwd_link
    ln -s /var/log /app/bloated_dir/cache/log_link
    ln -s ../../../etc/shadow /app/bloated_dir/cache/shadow_link

    # Create safe symlink (should NOT be removed)
    ln -s /app/bloated_dir/configs/c1.cfg /app/bloated_dir/logs/safe_link

    # Generate video
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=5 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='CRITICAL ALERT\nTARGET_DIR=/app/bloated_dir\nZIP SLIP DETECTED':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2" -c:v libx264 -y /app/extraction_incident.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

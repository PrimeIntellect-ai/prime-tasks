#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg zip unzip
    pip3 install pytest

    mkdir -p /home/user/dataset/archives
    mkdir -p /app/

    ffmpeg -f lavfi -i testsrc=duration=5:size=640x480:rate=30 -c:v libx264 /app/experiment_video.mp4

    ln -s /home/user/dataset/loop2 /home/user/dataset/loop1
    ln -s /home/user/dataset/loop1 /home/user/dataset/loop2
    ln -s /nonexistent_target /home/user/dataset/broken_link

    mkdir -p /tmp/valid_archive
    echo "data payload A" > /tmp/valid_archive/raw_data_101.dat
    echo "data payload B" > /tmp/valid_archive/raw_data_202.dat
    cd /tmp/valid_archive && zip -r /home/user/dataset/archives/valid_data.zip ./*
    rm -rf /tmp/valid_archive

    echo "This is not a valid zip file, it is corrupted data." > /home/user/dataset/archives/bad_data.zip

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

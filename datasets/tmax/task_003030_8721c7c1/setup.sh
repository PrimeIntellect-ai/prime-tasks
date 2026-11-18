#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++ valgrind
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate a dummy 5-second video
    ffmpeg -f lavfi -i color=c=black:s=128x128:d=5 -vcodec libx264 /app/test_video.mp4

    # Create corpus files
    echo "[INFO] [data [more data]]" > /app/corpus/clean/clean1.txt
    echo "[INFO] [data [[more data]" > /app/corpus/evil/evil1.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

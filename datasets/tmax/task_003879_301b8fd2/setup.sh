#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg bc gawk
    pip3 install pytest pandas

    mkdir -p /app
    # Create a 15-second dummy audio file for the task
    ffmpeg -f lavfi -i sine=frequency=1000:duration=15 -c:a pcm_s16le /app/recording.wav

    # Create the weights file
    echo "10.5,-0.2,0.8" > /app/weights.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

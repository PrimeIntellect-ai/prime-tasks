#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang
    pip3 install pytest requests

    # Create the app directory and generate a dummy audio file
    mkdir -p /app
    ffmpeg -f lavfi -i sine=frequency=1000:duration=7.5 /app/dataset.wav

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

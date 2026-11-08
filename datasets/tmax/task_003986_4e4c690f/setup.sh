#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak libsndfile1 ffmpeg
    pip3 install pytest

    # Create the audio directory and generate a sample spoken audio file
    mkdir -p /app/audio
    espeak -w /app/audio/sample.wav "The quick brown fox jumps over the lazy dog."

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

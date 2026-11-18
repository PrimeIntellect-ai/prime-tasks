#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron espeak ffmpeg libsndfile1
    pip3 install pytest

    # Create directories
    mkdir -p /app/data
    mkdir -p /home/user/pipeline
    mkdir -p /home/user/output

    # Generate the audio file
    espeak -w /app/data/field_recording.wav "The quick brown fox jumps over the lazy dog while the system monitors the acoustic levels."

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app/data

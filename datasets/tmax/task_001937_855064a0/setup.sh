#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang ffmpeg
    pip3 install pytest

    # Create the app directory
    mkdir -p /app

    # Generate the audio file
    ffmpeg -f lavfi -i sine=frequency=1000:duration=12.45 -ar 8000 -c:a pcm_s16le /app/voicemail_backup.wav

    # Create the user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git logrotate espeak ffmpeg
    pip3 install pytest

    # Create the audio fixture
    mkdir -p /app
    espeak -w /app/voicemail.wav "Attention, the system update has been deployed successfully."

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

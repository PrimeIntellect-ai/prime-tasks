#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install dependencies for audio processing, math, and networking
    apt-get install -y ffmpeg netcat-openbsd socat bc jq

    # Create the required directory and generate the input audio file
    mkdir -p /app
    ffmpeg -f lavfi -i "sine=frequency=1000:duration=10" -af "volume=-20dB" /app/test_signal.wav

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user

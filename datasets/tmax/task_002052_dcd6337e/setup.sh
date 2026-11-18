#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev espeak ffmpeg
    pip3 install pytest

    # Create the required directory and audio file
    mkdir -p /app
    espeak -w /app/interception.wav "hunter two security"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

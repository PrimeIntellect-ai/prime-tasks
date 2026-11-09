#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required system packages
    apt-get install -y ffmpeg gcc libc6-dev tzdata netcat-openbsd

    # Create the /app directory
    mkdir -p /app

    # Generate a dummy video file for the task
    ffmpeg -f lavfi -i testsrc=duration=2:size=320x240:rate=30 -c:v libx264 /app/surveillance.mp4

    # Create the user
    useradd -m -s /bin/bash user || true

    # Ensure permissions
    chmod -R 777 /home/user

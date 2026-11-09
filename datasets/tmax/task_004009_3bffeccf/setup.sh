#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install necessary system packages
    apt-get install -y g++ cron nlohmann-json3-dev espeak curl

    # Create the app directory and generate the audio file
    mkdir -p /app
    espeak -w /app/call_recording.wav "Hello I am calling because my internet connection is completely unresponsive and I demand an immediate cancellation of my subscription"

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app

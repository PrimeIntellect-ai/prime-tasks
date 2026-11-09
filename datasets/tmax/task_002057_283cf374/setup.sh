#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak-ng
    pip3 install pytest flask fastapi uvicorn python-multipart

    # Create the required audio file
    mkdir -p /app
    espeak-ng -w /app/secret_passphrase.wav "crimson skyline protocol"

    # Create user
    useradd -m -s /bin/bash user || true

    # Prepare artifacts directory
    mkdir -p /home/user/artifacts

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl cargo rustc espeak
    pip3 install pytest

    # Create the required directory
    mkdir -p /app

    # Generate the audio file with the secret passphrase
    espeak -w /app/intercept_77.wav "alpha tango sierra"

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /app
    chmod -R 777 /home/user

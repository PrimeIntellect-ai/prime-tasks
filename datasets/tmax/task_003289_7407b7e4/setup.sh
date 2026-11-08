#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install necessary tools for the agent and for generating the audio
    apt-get install -y gcc build-essential libmicrohttpd-dev espeak ffmpeg tar gzip curl wget

    # Create application directory
    mkdir -p /app

    # Generate the transmission audio file
    espeak -w /app/transmission.wav "The service must listen on port eight eight eight eight. The security token is omega cipher nine."

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user

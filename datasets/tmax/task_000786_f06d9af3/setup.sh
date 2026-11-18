#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake g++ make sox
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/project
    mkdir -p /app

    # Generate sample audio file (30 seconds, 44.1kHz, 16-bit mono)
    sox -n -r 44100 -c 1 -b 16 /app/sample_audio.wav synth 30 sine 440

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app

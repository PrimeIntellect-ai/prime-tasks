#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak gcc ffmpeg
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/evil/
    mkdir -p /app/corpus/clean/

    # Generate directive audio
    espeak -w /app/directive.wav "All records where the severity field is critical must be dropped immediately."

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

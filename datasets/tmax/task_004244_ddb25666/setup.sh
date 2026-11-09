#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc espeak ffmpeg
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/vm_auth.wav "purple dinosaur"
    chmod 644 /app/vm_auth.wav

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

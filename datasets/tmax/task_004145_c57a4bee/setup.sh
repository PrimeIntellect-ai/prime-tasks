#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc espeak
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/voicemail.wav "The emergency override token is seven three nine one."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

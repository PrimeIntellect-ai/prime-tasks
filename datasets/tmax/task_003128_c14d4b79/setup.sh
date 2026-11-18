#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/voicemail.wav "The access code is crimson butterfly protocol."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

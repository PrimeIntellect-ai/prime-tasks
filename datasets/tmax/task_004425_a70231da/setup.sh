#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc netcat-openbsd espeak ffmpeg
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/config_memo.wav "Set timeout to 120. Admin Alice. Set retries to 5. Admin Bob. Set timeout to 120. Admin Charlie. Set negative_cache to minus 10. Admin Dave. Set max_connections to 1000. Admin Eve."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

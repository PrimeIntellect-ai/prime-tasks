#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak gcc netcat-openbsd
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/voicemail.wav "Please update the mailing list server to use port eight zero two five and set the health check timeout to four seconds."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

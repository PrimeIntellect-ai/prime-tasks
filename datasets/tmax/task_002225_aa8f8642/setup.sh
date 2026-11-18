#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        curl \
        netcat-openbsd \
        espeak \
        ffmpeg

    pip3 install pytest

    mkdir -p /app
    espeak -w /app/incident_report.wav "database connection timeout in eu west one"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

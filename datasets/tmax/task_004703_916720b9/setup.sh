#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak cron
    pip3 install pytest

    mkdir -p /app/audio_logs
    espeak -w /app/audio_logs/dictation.wav "The mathematical foundations of data engineering require careful attention to timestamp alignment and rigorous data stratification. When building an etl pipeline, one must normalize incoming tokens effectively."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg flac
    pip3 install pytest numpy SpeechRecognition pydub flask fastapi uvicorn

    mkdir -p /app/data
    espeak -w /app/data/target_metric.wav "zero point zero seven"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

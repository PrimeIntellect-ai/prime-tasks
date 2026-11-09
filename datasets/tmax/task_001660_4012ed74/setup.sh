#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc ffmpeg espeak-ng curl pkg-config libpulse-dev

    pip3 install pytest hypothesis flask requests fastapi uvicorn SpeechRecognition soundfile numpy pocketsphinx

    mkdir -p /app/src /app/lib /app/tests /app/audio

    espeak-ng -w /app/audio/alert.wav "Build pipeline failed at network module"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest grpcio grpcio-tools SpeechRecognition pydub

    mkdir -p /app

    # Generate the audio file with the simulated speech
    espeak -w /app/etl_spikes.wav "EN 2023-10-01T10:00:00Z XYZ-123 FAILED. ES 2023-10-01T10:05:00Z XYZ-123 FAILED. ZH 2023-10-01T10:10:00Z ABC-999 SUCCESS"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

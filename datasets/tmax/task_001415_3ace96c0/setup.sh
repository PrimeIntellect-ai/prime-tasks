#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak gcc python3-pocketsphinx
    pip3 install pytest requests SpeechRecognition

    mkdir -p /app
    espeak "Listen on port eight zero eight zero. Use window size four." -w /app/config_audio.wav

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

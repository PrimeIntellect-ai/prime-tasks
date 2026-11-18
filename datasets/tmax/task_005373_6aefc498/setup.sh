#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang espeak ffmpeg flac
    pip3 install pytest SpeechRecognition

    # Create the app directory
    mkdir -p /app

    # Generate the audio file containing the secret word
    espeak -w /app/auth_token.wav "pineapple"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

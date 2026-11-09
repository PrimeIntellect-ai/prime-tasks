#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        socat \
        netcat-openbsd \
        curl \
        apache2-utils \
        espeak-ng \
        ffmpeg

    pip3 install pytest SpeechRecognition

    # Generate the audio fixture
    mkdir -p /app
    espeak-ng -w /app/alert.wav "Warning. Main build node failed. Please route traffic to fallback port eight four four three. The secret access token is gamma-ray-burst."

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

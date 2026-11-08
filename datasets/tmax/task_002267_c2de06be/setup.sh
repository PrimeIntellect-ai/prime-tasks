#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        build-essential \
        ffmpeg \
        espeak \
        wget \
        curl

    pip3 install pytest SpeechRecognition pydub

    # Create the audio file using espeak
    mkdir -p /app
    espeak -w /app/incident_alert.wav "Emergency. Connectivity lost. Node failure detected at IP ten dot zero dot forty dot fifty-five."

    # Create user and directories
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/net_logs/archive

    chmod -R 777 /home/user
    chmod -R 777 /app

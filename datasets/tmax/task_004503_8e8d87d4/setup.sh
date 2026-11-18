#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg curl
    pip3 install pytest numpy pandas scipy

    mkdir -p /app
    espeak -w /app/voicemail.wav "Hi, the parameters for the heat equation prototype are as follows: the thermal diffusivity alpha is zero point zero five. The domain length L is ten point zero. Please run the simulation until end time T equals twenty point zero."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

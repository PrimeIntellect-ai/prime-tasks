#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ espeak ffmpeg
    pip3 install pytest SpeechRecognition

    mkdir -p /app
    espeak -w /app/equation.wav "forty two point five multiplied by opening parenthesis three point one plus seven point eight closing parenthesis"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

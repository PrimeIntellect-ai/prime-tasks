#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget curl git build-essential gawk bc
    pip3 install pytest

    mkdir -p /app
    wget -O /app/voice_commands.wav https://raw.githubusercontent.com/ggerganov/whisper.cpp/master/samples/jfk.wav

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

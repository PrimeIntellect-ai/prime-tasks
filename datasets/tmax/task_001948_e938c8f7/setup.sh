#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make build-essential ffmpeg espeak git curl wget bc
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/sensor_dictation.wav "twenty point five, twenty one point two, nineteen point eight, unknown, twenty point one, ninety nine point nine, twenty point four, twenty point six, error, twenty point nine"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

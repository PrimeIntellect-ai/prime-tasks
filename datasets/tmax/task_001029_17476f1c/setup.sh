#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest networkx

    mkdir -p /app
    espeak -w /app/field_notes.wav "Socrates influences Plato. Plato influences Aristotle. Aristotle influences Alexander. Pythagoras influences Plato. Heraclitus influences Plato."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

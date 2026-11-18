#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak openssl ffmpeg
    pip3 install pytest flask fastapi uvicorn pyjwt cryptography requests

    mkdir -p /app
    echo -n "1e8a15fb92e21b14561b369ba0027f67" > /app/hash.txt
    espeak -w /app/instructions.wav "The JWT secret is a four digit pin. Crack the MD5 hash located at /app/hash.txt to find it."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg openssl
    pip3 install pytest pyelftools opencv-python-headless

    mkdir -p /app
    # Generate a short video containing the command
    ffmpeg -f lavfi -i color=c=black:s=1024x200:d=1 -vf "drawtext=text='openssl req -x509 -newkey rsa\:4096 -keyout key.pem -out cert.pem -days 365 -subj \"/CN=c2-backend.corp.attacker.net\"':fontcolor=white:fontsize=16:x=10:y=50" -c:v libx264 -preset ultrafast /app/incident_record.mp4

    # Create corpus directories
    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

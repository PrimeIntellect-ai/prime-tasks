#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        gcc \
        libssl-dev \
        openssl \
        fonts-liberation

    pip3 install pytest

    # Create directories
    mkdir -p /app

    # Generate video fixture
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=5 -vf "drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf:text='Echoing password... Secure_73**':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2" -c:v libx264 /app/incident_screen.mp4

    # Create user and required files
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/jail
    echo -n "f412d27c62c2f8216c026e643cc77bc6f01fbd0083ed28e359007fcd14736171" > /home/user/intercepted.hash

    chmod -R 777 /home/user
    chmod -R 777 /app

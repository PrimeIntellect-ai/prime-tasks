#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang sqlite3 build-essential git wget ffmpeg
    pip3 install pytest gTTS

    mkdir -p /app

    cat << 'EOF' > /app/gen_audio.py
from gtts import gTTS
import os

text = "Service Gateway calls Service Auth. Service Gateway calls Service Cart. Service Gateway calls Service Catalog. Service Auth calls Service DB. Service Auth calls Service Redis. Service Cart calls Service DB. Service Cart calls Service Inventory. Service Catalog calls Service Inventory. Service Inventory calls Service DB."
tts = gTTS(text)
tts.save("/app/temp.mp3")
os.system("ffmpeg -i /app/temp.mp3 -ar 16000 /app/network_topology.wav -y")
EOF

    python3 /app/gen_audio.py
    rm /app/gen_audio.py /app/temp.mp3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

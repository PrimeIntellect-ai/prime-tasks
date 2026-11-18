#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg git
    pip3 install pytest

    # Install CPU-only torch to save time and space, then whisper and gTTS
    pip3 install torch --index-url https://download.pytorch.org/whl/cpu
    pip3 install openai-whisper gTTS

    mkdir -p /app

    # Generate the test audio file
    python3 -c '
import os
from gtts import gTTS
tts = gTTS("the temperature sensor on unit four is malfunctioning")
tts.save("/tmp/temp.mp3")
os.system("ffmpeg -y -i /tmp/temp.mp3 -ar 16000 -ac 1 -c:a pcm_s16le /app/device_audio.wav >/dev/null 2>&1")
'
    rm -f /tmp/temp.mp3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

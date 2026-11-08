#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install pytest gTTS

# Create the required audio file
mkdir -p /app
python3 -c '
from gtts import gTTS
tts = gTTS("Observation forty-two: The blue-winged warbler was spotted near the northern creek.", lang="en")
tts.save("/app/temp.mp3")
'
ffmpeg -i /app/temp.mp3 /app/field_note.wav
rm /app/temp.mp3

# Create user
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app

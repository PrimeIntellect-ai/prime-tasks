#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ ffmpeg
    pip3 install pytest openai-whisper gTTS

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_audio.py
from gtts import gTTS
text = "Observation one: Fox eats Rabbit. Observation two: Rabbit eats Grass. Observation three: Fox eats Mouse. Observation four: Owl eats Mouse. Observation five: Owl eats Fox."
tts = gTTS(text)
tts.save('/tmp/ecosystem_log.mp3')
EOF
    python3 /tmp/gen_audio.py
    ffmpeg -i /tmp/ecosystem_log.mp3 -ar 16000 -ac 1 /app/ecosystem_log.wav
    rm /tmp/gen_audio.py /tmp/ecosystem_log.mp3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest gTTS

    mkdir -p /app

    cat << 'EOF' > /tmp/gen_audio.py
from gtts import gTTS
text = "We collected seventy two data points, um, and found a high variance in the quarterly metrics. Uh, the standard deviation was roughly four point five, like, which indicates significant outliers. We should probably review the logging pipeline to ensure data integrity."
tts = gTTS(text, lang='en')
tts.save('/app/dataset_recording.mp3')
EOF

    python3 /tmp/gen_audio.py
    ffmpeg -i /app/dataset_recording.mp3 -ar 16000 /app/dataset_recording.wav
    rm /app/dataset_recording.mp3 /tmp/gen_audio.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

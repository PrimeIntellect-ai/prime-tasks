#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        golang-go \
        curl \
        wget

    pip3 install pytest gTTS pydub

    mkdir -p /app
    mkdir -p /home/user/etl

    # Generate the audio file with specific timings
    cat << 'EOF' > /tmp/gen_audio.py
from gtts import gTTS
from pydub import AudioSegment
import os

def make_segment(text, target_duration_ms):
    tts = gTTS(text)
    tts.save("temp.mp3")
    audio = AudioSegment.from_mp3("temp.mp3")
    pad_len = target_duration_ms - len(audio)
    if pad_len > 0:
        audio += AudioSegment.silent(duration=pad_len)
    return audio

a1 = make_segment("Hello, thank you for calling support.", 5000)
a2 = make_segment("My account is locked and I cannot login to the system.", 10000)
a3 = make_segment("I understand. Let me help you unlock the account.", 7000)

final = a1 + a2 + a3
final.export("/app/call_recording.wav", format="wav")

if os.path.exists("temp.mp3"):
    os.remove("temp.mp3")
EOF

    python3 /tmp/gen_audio.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/etl
    chmod -R 777 /home/user
    chmod -R 777 /app

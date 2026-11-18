#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git make gcc g++ wget curl ffmpeg
    pip3 install pytest gTTS pydub

    mkdir -p /app

    cat << 'EOF' > /tmp/gen_audio.py
from gtts import gTTS
from pydub import AudioSegment
import os

# Generate audio parts
tts1 = gTTS("Welcome to the system.", lang='en')
tts1.save("/tmp/1.mp3")
tts2 = gTTS("Please enter your password. Please enter your password.", lang='en')
tts2.save("/tmp/2.mp3")
tts3 = gTTS("Login successful!", lang='en')
tts3.save("/tmp/3.mp3")

a1 = AudioSegment.from_mp3("/tmp/1.mp3")
a2 = AudioSegment.from_mp3("/tmp/2.mp3")
a3 = AudioSegment.from_mp3("/tmp/3.mp3")

def pad_to(audio, duration_ms):
    if len(audio) < duration_ms:
        return audio + AudioSegment.silent(duration=duration_ms - len(audio))
    return audio[:duration_ms]

a1 = pad_to(a1, 10000)
a2 = pad_to(a2, 10000)
a3 = pad_to(a3, 10000)

final = a1 + a2 + a3
# Whisper requires 16kHz, 1 channel, 16-bit
final = final.set_frame_rate(16000).set_channels(1).set_sample_width(2)
final.export("/app/dialogue_raw.wav", format="wav")
EOF

    python3 /tmp/gen_audio.py
    rm /tmp/*.mp3 /tmp/gen_audio.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate the audio briefing
    espeak -w /app/admin_instructions.wav "The secret authorization token for this batch is BlueFalcon99."

    # Generate the corpus
    cat << 'EOF' > /tmp/gen_corpus.py
import os
import zipfile
import wave

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

def create_wav(path, channels=2, sampwidth=2, framerate=44100):
    with wave.open(path, 'wb') as wf:
        wf.setnchannels(channels)
        wf.setsampwidth(sampwidth)
        wf.setframerate(framerate)
        wf.writeframes(b'\x00' * (channels * sampwidth * 100))

def create_zip(path, token="BlueFalcon99", channels=2, sampwidth=2, framerate=44100, valid_zip=True, missing_meta=False, missing_wav=False):
    if not valid_zip:
        with open(path, 'wb') as f:
            f.write(b'PK\x03\x04garbage data that makes this zip invalid')
        return

    with zipfile.ZipFile(path, 'w') as zf:
        if not missing_meta:
            zf.writestr('metadata.txt', f"Token: {token}\n")
        if not missing_wav:
            wav_path = path + '.wav'
            create_wav(wav_path, channels, sampwidth, framerate)
            zf.write(wav_path, 'audio.wav')
            os.remove(wav_path)

# Clean corpus
for i in range(10):
    create_zip(f'/app/corpus/clean/clean_{i}.zip')

# Evil corpus
evil_configs = [
    {"token": "WrongToken123"},
    {"framerate": 48000},
    {"channels": 1},
    {"sampwidth": 1}, # 8-bit
    {"valid_zip": False},
    {"missing_meta": True},
    {"missing_wav": True},
]

for i in range(20):
    config = evil_configs[i % len(evil_configs)]
    create_zip(f'/app/corpus/evil/evil_{i}.zip', **config)
EOF

    python3 /tmp/gen_corpus.py
    rm /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

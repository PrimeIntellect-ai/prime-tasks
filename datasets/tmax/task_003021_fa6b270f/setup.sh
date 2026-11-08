#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git wget build-essential
    pip3 install pytest

    mkdir -p /app/models
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Clone whisper.cpp
    git clone https://github.com/ggerganov/whisper.cpp.git /app/whisper.cpp

    # Download whisper model
    wget -O /app/models/ggml-base.en.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin

    # Create model weights
    cat << 'EOF' > /app/model_weights.csv
hash,weight
437,2.0
520,2.0
443,2.0
223,2.0
562,2.0
EOF

    # Generate dummy WAV files
    cat << 'EOF' > /tmp/gen_wav.py
import wave
import struct
import os

def create_wav(filename):
    with wave.open(filename, 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        # write 0.1 second of silence
        for _ in range(1600):
            w.writeframes(struct.pack('h', 0))

create_wav('/app/reference_sample.wav')
for i in range(5):
    create_wav(f'/app/corpus/clean/clean_{i}.wav')
    create_wav(f'/app/corpus/evil/evil_{i}.wav')
EOF
    python3 /tmp/gen_wav.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    # Generate a dummy audio.wav
    mkdir -p /fixture
    cat << 'EOF' > /fixture/gen_wav.py
import wave
import struct
import math

sample_rate = 44100
duration = 1.0 # seconds
freq = 440.0

wav = wave.open('/fixture/audio.wav', 'wb')
wav.setnchannels(1)
wav.setsampwidth(2)
wav.setframerate(sample_rate)

frames = []
for i in range(int(sample_rate * duration)):
    val = int(32767.0 * math.sin(2.0 * math.pi * freq * i / sample_rate))
    frames.append(struct.pack('<h', val))

wav.writeframes(b''.join(frames))
wav.close()
EOF
    python3 /fixture/gen_wav.py

    mkdir -p /app/blobs
    cp /fixture/audio.wav /app/blobs/blob_001
    echo "System config data" > /app/blobs/blob_002
    echo "User database dump" > /app/blobs/blob_003

    cat << 'EOF' > /app/backup_manifest.csv
blob_id,original_path,file_type
blob_001,logs/voice_memo_2023.wav,audio
blob_002,etc/sysconfig.txt,text
blob_003,db/users.sql,text
EOF

    chmod -R 777 /app
    chmod -R 777 /fixture

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

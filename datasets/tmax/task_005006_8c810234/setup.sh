#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak build-essential
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate suspicious recording
    espeak -w /app/suspicious_recording.wav "the system is compromised"

    # Generate clean and evil WAV files
    python3 -c "
import struct
import os

def make_wav(path, data_size):
    with open(path, 'wb') as f:
        f.write(b'RIFF')
        f.write(struct.pack('<I', 36 + data_size))
        f.write(b'WAVE')
        f.write(b'fmt ')
        f.write(struct.pack('<I', 16))
        f.write(struct.pack('<H', 1)) # PCM
        f.write(struct.pack('<H', 1)) # Channels
        f.write(struct.pack('<I', 44100)) # Sample rate
        f.write(struct.pack('<I', 44100 * 2)) # Byte rate
        f.write(struct.pack('<H', 2)) # Block align
        f.write(struct.pack('<H', 16)) # Bits per sample
        f.write(b'data')
        f.write(struct.pack('<I', data_size))
        f.write(b'\x00' * data_size)

def make_evil_wav(path):
    with open(path, 'wb') as f:
        f.write(b'RIFF')
        f.write(struct.pack('<I', 36 + 100))
        f.write(b'WAVE')
        f.write(b'fmt ')
        f.write(struct.pack('<I', 16))
        f.write(struct.pack('<H', 1))
        f.write(struct.pack('<H', 1))
        f.write(struct.pack('<I', 44100))
        f.write(struct.pack('<I', 44100 * 2))
        f.write(struct.pack('<H', 2))
        f.write(struct.pack('<H', 16))
        f.write(b'data')
        f.write(struct.pack('<I', 0xFFFFFF00)) # Evil size
        f.write(b'\x00' * 100)

make_wav('/app/corpus/clean/clean1.wav', 100)
make_wav('/app/corpus/clean/clean2.wav', 200)

make_evil_wav('/app/corpus/evil/evil1.wav')
make_evil_wav('/app/corpus/evil/evil2.wav')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

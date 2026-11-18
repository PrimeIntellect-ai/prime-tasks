#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak build-essential
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate last_request.wav
    espeak -w /app/last_request.wav "The payload starts with the magic word: BAZINGA"

    # Generate core dump, clean, and evil corpora
    python3 -c "
import os
import wave
import struct
import random

# Generate service.core
with open('/app/service.core', 'wb') as f:
    data = bytearray(os.urandom(10 * 1024 * 1024))
    offset = random.randint(0, len(data) - 100)
    data[offset:offset+23] = b'BAZINGA9F8E7D6C5B4A3928'
    f.write(data)

# Generate clean and evil WAVs
for i in range(50):
    clean_path = f'/app/corpus/clean/clean_{i}.wav'
    with wave.open(clean_path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(44100)
        w.writeframes(b'\x00' * 44100 * 2)

    evil_path = f'/app/corpus/evil/evil_{i}.wav'
    with open(clean_path, 'rb') as f:
        clean_data = bytearray(f.read())

    junk_chunk = b'JUNK' + struct.pack('<I', 0x0FFFFFFF) + b'A'*8
    evil_data = clean_data[:12] + junk_chunk + clean_data[12:]

    riff_size = len(evil_data) - 8
    evil_data[4:8] = struct.pack('<I', riff_size)

    with open(evil_path, 'wb') as f:
        f.write(evil_data)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

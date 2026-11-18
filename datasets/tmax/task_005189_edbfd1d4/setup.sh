#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc socat
    pip3 install pytest requests numpy

    # Create app directory
    mkdir -p /app

    # Generate the raw WAV file
    cat << 'EOF' > /tmp/generate_wav.py
import wave
import struct
import math

with wave.open('/app/alert_raw.wav', 'wb') as wav_file:
    wav_file.setnchannels(1)
    wav_file.setsampwidth(2)
    wav_file.setframerate(16000)

    duration = 2.0
    freq = 440.0
    num_samples = int(duration * 16000)

    for i in range(num_samples):
        value = int(32767.0 * math.sin(2.0 * math.pi * freq * i / 16000))
        data = struct.pack('<h', value)
        wav_file.writeframesraw(data)
EOF
    python3 /tmp/generate_wav.py
    rm /tmp/generate_wav.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

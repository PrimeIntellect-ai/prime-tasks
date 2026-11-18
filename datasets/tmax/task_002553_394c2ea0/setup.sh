#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        expect \
        netcat-openbsd \
        cron \
        multimon-ng \
        sox

    pip3 install pytest

    # Create app directory
    mkdir -p /app

    # Generate the DTMF audio file for PIN 4092
    cat << 'EOF' > /tmp/generate_dtmf.py
import wave
import math
import struct

sample_rate = 8000
duration = 0.5

# DTMF frequencies for 4, 0, 9, 2
tones = [
    (770, 1209), # 4
    (941, 1336), # 0
    (852, 1477), # 9
    (697, 1336)  # 2
]

with wave.open('/app/telemetry.wav', 'w') as wav_file:
    wav_file.setnchannels(1)
    wav_file.setsampwidth(2)
    wav_file.setframerate(sample_rate)

    for f1, f2 in tones:
        for i in range(int(sample_rate * duration)):
            t = float(i) / sample_rate
            value = int(32767.0 * 0.5 * (math.sin(2.0 * math.pi * f1 * t) + math.sin(2.0 * math.pi * f2 * t)))
            data = struct.pack('<h', value)
            wav_file.writeframesraw(data)
        # silence between tones
        for i in range(int(sample_rate * 0.2)):
            wav_file.writeframesraw(struct.pack('<h', 0))
EOF

    python3 /tmp/generate_dtmf.py
    rm /tmp/generate_dtmf.py

    # Create user
    useradd -m -s /bin/bash user || true

    # Ensure proper permissions
    chmod -R 777 /home/user

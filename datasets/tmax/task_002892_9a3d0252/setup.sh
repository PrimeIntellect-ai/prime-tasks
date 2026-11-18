#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang cargo rustc protobuf-compiler curl
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/generate_wav.py
import wave
import math
import struct

def generate_tone(f1, f2, duration, sample_rate=8000):
    samples = []
    for i in range(int(duration * sample_rate)):
        t = float(i) / sample_rate
        val = math.sin(2 * math.pi * f1 * t) + math.sin(2 * math.pi * f2 * t)
        val = val * 0.5 * 32767
        samples.append(int(val))
    return samples

dtmf = {
    '8': (852, 1336),
    'C': (852, 1633),
    '5': (770, 1336),
    'A': (697, 1633),
    '2': (697, 1336)
}

sequence = ['8', 'C', '5', 'A', '2']
sample_rate = 8000
duration = 0.2
pause_duration = 0.1

all_samples = []
for char in sequence:
    f1, f2 = dtmf[char]
    all_samples.extend(generate_tone(f1, f2, duration, sample_rate))
    all_samples.extend([0] * int(pause_duration * sample_rate))

with wave.open('/app/equation.wav', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sample_rate)
    for s in all_samples:
        w.writeframes(struct.pack('<h', s))
EOF
    python3 /tmp/generate_wav.py

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/project
    chmod -R 777 /home/user
    chmod -R 777 /app

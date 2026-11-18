#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nasm gcc build-essential
    pip3 install pytest flask numpy scipy requests

    mkdir -p /app

    cat << 'EOF' > /tmp/gen_audio.py
import wave
import struct
import math

def generate_dtmf(sequence, filename):
    frequencies = {
        '1': (697, 1209), '2': (697, 1336), '3': (697, 1477),
        '4': (770, 1209), '5': (770, 1336), '6': (770, 1477),
        '7': (852, 1209), '8': (852, 1336), '9': (852, 1477),
        '*': (941, 1209), '0': (941, 1336), '#': (941, 1477)
    }
    sample_rate = 44100
    duration = 0.2
    pause = 0.1

    with wave.open(filename, 'w') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(sample_rate)

        for char in sequence:
            f1, f2 = frequencies[char]
            for i in range(int(sample_rate * duration)):
                t = float(i) / sample_rate
                val = int(32767.0 * 0.5 * (math.sin(2 * math.pi * f1 * t) + math.sin(2 * math.pi * f2 * t)))
                f.writeframesraw(struct.pack('<h', val))
            for i in range(int(sample_rate * pause)):
                f.writeframesraw(struct.pack('<h', 0))

generate_dtmf('8675309', '/app/signal.wav')
EOF

    python3 /tmp/gen_audio.py

    echo "cherry\napple\nelderberry" | base64 > /app/data_A.b64
    echo "banana\ndate\napple" | base64 > /app/data_B.b64

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

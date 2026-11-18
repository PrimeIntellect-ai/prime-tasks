#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc logrotate openssl
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file
    cat << 'EOF' > /tmp/gen_audio.py
import wave
import struct
import random

sample_rate = 44100
duration_s = 15
num_samples = sample_rate * duration_s

samples = [random.randint(-4000, 4000) for _ in range(num_samples)]

def add_event(start_s, dur_s):
    start_i = int(start_s * sample_rate)
    dur_i = int(dur_s * sample_rate)
    for i in range(start_i, start_i + dur_i):
        samples[i] = random.choice([random.randint(13000, 30000), random.randint(-30000, -13000)])

add_event(2.150, 0.300)
add_event(5.420, 0.150)
add_event(11.050, 0.800)

with wave.open('/app/machine_audio.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(sample_rate)
    for s in samples:
        f.writeframes(struct.pack('<h', s))
EOF
    python3 /tmp/gen_audio.py
    rm /tmp/gen_audio.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

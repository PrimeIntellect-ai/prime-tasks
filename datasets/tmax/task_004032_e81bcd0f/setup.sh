#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sox ffmpeg build-essential
    pip3 install pytest

    cat << 'EOF' > /tmp/generate_audio.py
import os
import struct
import random
import math
import wave

def generate_clean(filename):
    A = 3141.5
    freq = 400.0
    sample_rate = 8000
    samples = []
    for i in range(sample_rate):
        val = int(A * math.sin(2 * math.pi * freq * i / sample_rate))
        samples.append(val)
    if filename:
        with open(filename, 'wb') as f:
            f.write(struct.pack('<' + 'h'*len(samples), *samples))
    return samples

def generate_evil(filename):
    A = 1000
    sample_rate = 8000
    samples = []
    for i in range(sample_rate):
        val = random.randint(-A, A)
        samples.append(val)
    if filename:
        with open(filename, 'wb') as f:
            f.write(struct.pack('<' + 'h'*len(samples), *samples))
    return samples

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)
os.makedirs('/app/hidden_corpus/clean', exist_ok=True)
os.makedirs('/app/hidden_corpus/evil', exist_ok=True)

for i in range(20):
    generate_clean(f'/app/corpus/clean/{i}.pcm')
    generate_evil(f'/app/corpus/evil/{i}.pcm')
    generate_clean(f'/app/hidden_corpus/clean/{i}.pcm')
    generate_evil(f'/app/hidden_corpus/evil/{i}.pcm')

all_samples = []
for i in range(10):
    if i % 2 == 0:
        all_samples.extend(generate_clean(None))
    else:
        all_samples.extend(generate_evil(None))

with wave.open('/app/source.wav', 'wb') as wav_file:
    wav_file.setnchannels(1)
    wav_file.setsampwidth(2)
    wav_file.setframerate(8000)
    wav_file.writeframes(struct.pack('<' + 'h'*len(all_samples), *all_samples))
EOF

    python3 /tmp/generate_audio.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

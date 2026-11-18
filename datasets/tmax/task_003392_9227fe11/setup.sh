#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /home/user/math_pipeline
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Create processor.py
    cat << 'EOF' > /home/user/math_pipeline/processor.py
import json
import os

def update_metrics(key, value):
    filepath = '/home/user/math_pipeline/metrics.json'
    if not os.path.exists(filepath):
        with open(filepath, 'w') as f:
            json.dump({}, f)
    with open(filepath, 'r') as f:
        data = json.load(f)
    data[key] = value
    with open(filepath, 'w') as f:
        json.dump(data, f)
EOF

    # Create wav_parser.py
    cat << 'EOF' > /home/user/math_pipeline/wav_parser.py
import struct

def parse_wav(filepath):
    with open(filepath, 'rb') as f:
        riff = f.read(4)
        size = struct.unpack('<I', f.read(4))[0]
        wave = f.read(4)
        fmt = f.read(4)
        fmt_size = struct.unpack('<I', f.read(4))[0]
        audio_format = struct.unpack('<H', f.read(2))[0]
        num_channels = struct.unpack('<H', f.read(2))[0]
        sample_rate = struct.unpack('<I', f.read(4))[0]
        byte_rate = struct.unpack('<I', f.read(4))[0]
        block_align = struct.unpack('<H', f.read(2))[0]
        bits_per_sample = struct.unpack('<H', f.read(2))[0]
        data_chunk_header = f.read(4)
        if data_chunk_header != b'data':
            raise ValueError("Expected data chunk")
        return True
EOF

    # Create test_pipeline.py
    cat << 'EOF' > /home/user/math_pipeline/test_pipeline.py
import threading
import pytest
from processor import update_metrics
from wav_parser import parse_wav

def test_race_condition():
    threads = []
    for i in range(50):
        t = threading.Thread(target=update_metrics, args=(f"key_{i}", i))
        threads.append(t)
        t.start()
    for t in threads:
        t.join()

def test_wav_parser():
    assert parse_wav('test_18byte.wav')
EOF

    # Generate test data and corpora
    python3 -c "
import wave
import struct
import os

with open('/home/user/math_pipeline/test_18byte.wav', 'wb') as f:
    f.write(b'RIFF$\x00\x00\x00WAVEfmt \x12\x00\x00\x00\x01\x00\x01\x00D\xac\x00\x00\x88X\x01\x00\x02\x00\x10\x00\x00\x00data\x00\x00\x00\x00')

def create_wav(path, evil=False):
    with wave.open(path, 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(44100)
        frames = []
        val = 0
        for i in range(100):
            frames.append(struct.pack('<h', val))
            if evil and i == 50:
                val += 25000
                if val > 32767: val = 32767
            else:
                val += 10
        w.writeframes(b''.join(frames))

for i in range(10):
    create_wav(f'/app/corpora/clean/clean_{i}.wav', evil=False)
    create_wav(f'/app/corpora/evil/evil_{i}.wav', evil=True)
"

    # Generate mystery signal
    espeak -w /app/mystery_signal.wav "The constant is three point one four one five nine"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app

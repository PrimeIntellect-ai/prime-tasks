#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install --default-timeout=100 pytest numpy

    # Install Rust
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/opt/rust/bin:${PATH}"
    chmod -R 777 /opt/rust

    # Generate audio fixture
    cat << 'EOF' > /tmp/generate_audio.py
import numpy as np
import wave
import struct
import os

os.makedirs('/app', exist_ok=True)

sample_rate = 8000
duration = 1.0
frequencies = [400, 800, 500, 1200, 300, 900]

with wave.open('/app/sensor_stream.wav', 'w') as wav_file:
    wav_file.setnchannels(1)
    wav_file.setsampwidth(2)
    wav_file.setframerate(sample_rate)

    for freq in frequencies:
        t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)
        audio = (np.sin(2 * np.pi * freq * t) * 32767.0).astype(np.int16)
        for sample in audio:
            wav_file.writeframes(struct.pack('h', sample))
EOF
    python3 /tmp/generate_audio.py
    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

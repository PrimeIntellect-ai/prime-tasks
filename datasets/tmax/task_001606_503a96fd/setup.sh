#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev netcat-openbsd socat
    pip3 install pytest numpy

    mkdir -p /app

    cat << 'EOF' > /tmp/gen_data.py
import numpy as np
import wave

# Generate baseline_metrics.csv
np.random.seed(42)
energy = np.random.normal(10000, 1000, 1000)
zcr = np.random.normal(0.12, 0.02, 1000)
with open('/app/baseline_metrics.csv', 'w') as f:
    for e, z in zip(energy, zcr):
        f.write(f"{e},{z}\n")

# Generate anomaly_candidate.wav
sample_rate = 44100
duration = 1.0
t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)
audio = 10000 * np.sin(2 * np.pi * 440 * t) + np.random.normal(0, 1000, len(t))
audio = np.clip(audio, -32768, 32767).astype(np.int16)

with wave.open('/app/anomaly_candidate.wav', 'w') as wav_file:
    wav_file.setnchannels(1)
    wav_file.setsampwidth(2)
    wav_file.setframerate(sample_rate)
    wav_file.writeframes(audio.tobytes())
EOF

    python3 /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

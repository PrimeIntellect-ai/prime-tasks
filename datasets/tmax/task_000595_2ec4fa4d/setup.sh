#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git cron
    pip3 install pytest numpy scipy pandas

    mkdir -p /app
    mkdir -p /home/user/workspace

    cat << 'EOF' > /tmp/generate_wav.py
import numpy as np
from scipy.io import wavfile

loads = [45.0, 52.1, 60.5, 42.0, 39.5, 70.2, 85.0, 91.5, 40.0, 38.5, 45.6, 50.0, 55.5, 60.1, 62.3, 75.0, 80.0, 82.5, 88.0, 95.5, 30.0, 35.5, 40.0, 42.5, 45.0, 50.0, 52.5, 60.0, 65.5, 70.0]
sample_rate = 44100
freq = 1000.0

audio_data = []

for load in loads:
    duration_ms = load * 10
    duration_s = duration_ms / 1000.0
    t = np.linspace(0, duration_s, int(sample_rate * duration_s), endpoint=False)
    beep = np.sin(2 * np.pi * freq * t)
    audio_data.append(beep)

    # 0.5s silence
    silence = np.zeros(int(sample_rate * 0.5))
    audio_data.append(silence)

# remove last silence
audio_data = audio_data[:-1]
final_audio = np.concatenate(audio_data)

# normalize to 16-bit PCM
final_audio = np.int16(final_audio * 32767)

wavfile.write('/app/telemetry.wav', sample_rate, final_audio)
EOF

    python3 /tmp/generate_wav.py
    rm /tmp/generate_wav.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app

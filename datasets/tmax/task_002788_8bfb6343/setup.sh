#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sox gawk
pip3 install pytest numpy pandas

mkdir -p /app

cat << 'EOF' > /tmp/setup.py
import numpy as np
import wave
import struct
import subprocess

# Generate dummy sensor data
sample_rate = 8000
duration = 1.0
t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)
signal = np.sin(2 * np.pi * 5 * t) * 0.8 + np.random.normal(0, 0.05, len(t))

# Introduce dropouts (exact 0s)
signal[2000:2500] = 0.0
signal[5000:5100] = 0.0

# Ensure first is not zero
if signal[0] == 0:
    signal[0] = 0.1

# Save as WAV
wav_path = '/app/sensor.wav'
with wave.open(wav_path, 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(sample_rate)
    # Convert to 16-bit integers
    audio_data = (signal * 32767).astype(np.int16)
    f.writeframes(audio_data.tobytes())

# Generate ground truth
# Re-read using sox logic to mimic agent behavior
dat_output = subprocess.check_output(['sox', wav_path, '-t', 'dat', '-']).decode('utf-8')
lines = dat_output.strip().split('\n')
data = []
for line in lines:
    if line.startswith(';') or not line.strip():
        continue
    parts = line.split()
    time_val = float(parts[0])
    amp = float(parts[1])
    data.append([time_val, amp])

data = np.array(data)
abs_amp = np.abs(data[:, 1])

# Impute
imputed = np.zeros_like(abs_amp)
last_val = abs_amp[0]
for i in range(len(abs_amp)):
    if abs_amp[i] == 0.0:
        imputed[i] = last_val
    else:
        imputed[i] = abs_amp[i]
        last_val = abs_amp[i]

# Normalize
max_val = np.max(imputed)
normalized = imputed / max_val

# Rolling average (5-sample)
smoothed = np.zeros_like(normalized)
for i in range(len(normalized)):
    start_idx = max(0, i - 4)
    smoothed[i] = np.mean(normalized[start_idx:i+1])

# Write ground truth
with open('/app/ground_truth.csv', 'w') as f:
    for i in range(len(data)):
        f.write(f"{data[i,0]:.8f},{smoothed[i]:.8f}\n")
EOF

python3 /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    mkdir -p /app
    cat << 'EOF' > /tmp/setup.py
import os
import wave
import struct
import numpy as np

# Generate audio fixture
np.random.seed(42)
num_samples = 100000
train_size = int(num_samples * 0.7)
test_size = num_samples - train_size

# Generate signal (telemetry)
signal = np.random.randn(num_samples) * 5000 + 1000  # mean ~1000, std ~5000
signal = np.clip(signal, -32768, 32767).astype(np.int16)

os.makedirs('/app', exist_ok=True)
with wave.open('/app/telemetry.wav', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(8000)
    w.writeframes(signal.tobytes())

# Generate ground truth
train_signal = signal[:train_size].astype(np.float64)
test_signal = signal[train_size:].astype(np.float64)

train_mean = np.mean(train_signal)
train_std = np.std(train_signal, ddof=0) 

true_standardized_test = (test_signal - train_mean) / train_std
with open('/app/ground_truth_test.bin', 'wb') as f:
    f.write(true_standardized_test.tobytes())
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

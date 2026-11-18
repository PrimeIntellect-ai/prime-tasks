#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /app

    python3 -c "
import wave
import struct
import json
import numpy as np
import os

os.makedirs('/app', exist_ok=True)

# 1. Create metadata.dat
metadata = {
    'sensor_id': 'T-800',
    'min_valid': 1000,
    'max_valid': 9000
}
with open('/app/metadata.dat', 'wb') as f:
    f.write(json.dumps(metadata).encode('cp500'))

# 2. Create telemetry.wav
np.random.seed(42)
n_samples = 10000
true_changepoint = 3450

# Base signal
signal = np.zeros(n_samples)
signal[:true_changepoint] = np.random.normal(3000, 200, true_changepoint)
signal[true_changepoint:] = np.random.normal(6000, 200, n_samples - true_changepoint)

# Inject out-of-bounds anomalies (to test constraint validation)
anomaly_indices = np.random.choice(n_samples, 50, replace=False)
for idx in anomaly_indices:
    if np.random.rand() > 0.5:
        signal[idx] = np.random.uniform(15000, 30000) # Exceeds max_valid
    else:
        signal[idx] = np.random.uniform(-10000, 0)    # Below min_valid

# Ensure first sample is valid
signal[0] = 3000

# Write to WAV
with wave.open('/app/telemetry.wav', 'w') as wav_file:
    wav_file.setnchannels(1)
    wav_file.setsampwidth(2) # 16-bit
    wav_file.setframerate(10)

    # Pack data
    packed_data = struct.pack(f'<{n_samples}h', *[int(x) for x in signal])
    wav_file.writeframes(packed_data)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

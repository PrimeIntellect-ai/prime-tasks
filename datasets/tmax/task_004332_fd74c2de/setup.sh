#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install --default-timeout=100 pytest numpy scipy

mkdir -p /app
cat << 'EOF' > /tmp/generate_audio.py
import numpy as np
from scipy.io import wavfile

sample_rate = 44100
duration = 30
samples = np.zeros(sample_rate * duration, dtype=np.int16)

start_idx = int(12.5 * sample_rate)
end_idx = start_idx + sample_rate

t = np.linspace(0, 1, sample_rate, False)
burst = np.sin(2 * np.pi * 440 * t) * 30000
samples[start_idx:end_idx] = burst.astype(np.int16)

wavfile.write('/app/telemetry.wav', sample_rate, samples)
EOF

python3 /tmp/generate_audio.py

mkdir -p /home/user/manifests
cat << 'EOF' > /home/user/manifests/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sensor-processor
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: main
        image: processor:latest
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git build-essential
pip3 install pytest numpy

# Setup kissfft
git clone https://github.com/mborgerding/kissfft.git /app/kissfft
cd /app/kissfft
git checkout 1.31.1 || git checkout v1.31.1 || true

# Apply perturbation
sed -i 's/#define kiss_fft_scalar float/#define kiss_fft_scalar int/g' /app/kissfft/kiss_fft.h

# Generate corpus
python3 -c "
import os
import numpy as np

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

N = 1024
t = np.arange(N)

for i in range(10):
    # Clean: low freq sines + noise
    freq1 = np.random.uniform(5, 20)
    freq2 = np.random.uniform(30, 80)
    signal = np.sin(2 * np.pi * freq1 * t / N) + 0.5 * np.sin(2 * np.pi * freq2 * t / N)
    signal += np.random.normal(0, 0.1, N)

    with open(f'/app/corpus/clean/clean_{i}.txt', 'w') as f:
        for val in signal:
            f.write(f'{val:.6f}\n')

    # Evil: clean + high freq at bin 425
    evil_signal = signal + 0.5 * np.sin(2 * np.pi * 425 * t / N)
    with open(f'/app/corpus/evil/evil_{i}.txt', 'w') as f:
        for val in evil_signal:
            f.write(f'{val:.6f}\n')
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

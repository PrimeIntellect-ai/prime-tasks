#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy

    mkdir -p /app

    # Generate test_signal.wav with ~1.5 million samples
    python3 -c "
import numpy as np
import scipy.io.wavfile as wav

sample_rate = 44100
num_samples = 1500000
t = np.linspace(0, num_samples / sample_rate, num_samples, endpoint=False)
signal = np.sin(2 * np.pi * 440 * t)
signal_int16 = np.int16(signal * 32767)
wav.write('/app/test_signal.wav', sample_rate, signal_int16)
"

    mkdir -p /home/user
    cat << 'EOF' > /home/user/slow_filter.py
def slow_convolve(signal: list[float], kernel: list[float]) -> list[float]:
    n = len(signal)
    m = len(kernel)
    result = [0.0] * (n + m - 1)
    for i in range(n):
        for j in range(m):
            result[i + j] += signal[i] * kernel[j]
    return result
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

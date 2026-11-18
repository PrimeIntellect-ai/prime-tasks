#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_env.py
import math

# Create data.txt
sequence = "TTAGCATGCGATCGTAGCATGCTAGCTA" # Length 28
# Primer "ATGCGAT" is at index 5. Length 7.
# Payload starts at index 12.
# 50 samples starting from index 120 to 169.
signal = [math.sin(i * 0.25) + 0.5 * math.cos(i * 0.1) for i in range(280)]

with open('/home/user/data.txt', 'w') as f:
    f.write(sequence + '\n')
    f.write(','.join(f"{x:.6f}" for x in signal) + '\n')

# Compute expected DFT
N = 50
extracted_signal = signal[120:170]
expected_csv = "Bin,Magnitude\n"
for k in range(N):
    re = 0.0
    im = 0.0
    for n in range(N):
        angle = 2.0 * math.pi * k * n / N
        re += extracted_signal[n] * math.cos(angle)
        im -= extracted_signal[n] * math.sin(angle)
    mag = math.sqrt(re*re + im*im)
    expected_csv += f"{k},{mag:.4f}\n"

with open('/home/user/.expected_features.csv', 'w') as f:
    f.write(expected_csv)
EOF

    python3 /tmp/setup_env.py

    chmod -R 777 /home/user

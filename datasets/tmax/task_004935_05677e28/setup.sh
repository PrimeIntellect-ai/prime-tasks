#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest numpy scipy

cat << 'EOF' > /tmp/setup.py
import os
import wave
import struct
import math
import numpy as np

# Create directories
os.makedirs('/app/audio', exist_ok=True)
os.makedirs('/app/tools', exist_ok=True)
os.makedirs('/home/user', exist_ok=True)

# Ground truth parameters
A_true = 0.85
gamma_true = 2.5
f_true = 440.0
sample_rate = 8000
num_samples = 8000

# Generate audio
t = np.arange(num_samples) / sample_rate
y = A_true * np.exp(-gamma_true * t) * np.sin(2 * np.pi * f_true * t)

# Add a tiny bit of noise to make the optimization realistic but still easy
np.random.seed(42)
y_noisy = y + np.random.normal(0, 0.005, num_samples)

# Normalize to 16-bit integer range
y_int16 = np.int16(y_noisy * 32767)

with wave.open('/app/audio/decay_signal.wav', 'w') as wav_file:
    wav_file.setnchannels(1)
    wav_file.setsampwidth(2)
    wav_file.setframerate(sample_rate)
    for sample in y_int16:
        wav_file.writeframes(struct.pack('h', sample))

# Create the C tool wav2csv.c
c_code = """
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <input.wav> <output.csv>\\n", argv[0]);
        return 1;
    }

    FILE *in = fopen(argv[1], "rb");
    FILE *out = fopen(argv[2], "w");
    if (!in || !out) return 1;

    // Skip 44 byte WAV header (naive approach for this controlled environment)
    fseek(in, 44, SEEK_SET);

    int16_t sample;
    while (fread(&sample, sizeof(int16_t), 1, in) == 1) {
        fprintf(out, "%f\\n", sample / 32768.0);
    }

    fclose(in);
    fclose(out);
    return 0;
}
"""
with open('/app/tools/wav2csv.c', 'w') as f:
    f.write(c_code)
EOF

python3 /tmp/setup.py

cat << 'EOF' > /tmp/verify.py
import json
import sys
import numpy as np
import os

def main():
    if not os.path.exists('/home/user/params.json'):
        print("Error: /home/user/params.json not found")
        sys.exit(1)

    with open('/home/user/params.json', 'r') as f:
        params = json.load(f)

    A = params.get('A', 0)
    gamma = params.get('gamma', 0)
    f_val = params.get('f', 0)

    # True parameters
    A_true = 0.85
    gamma_true = 2.5
    f_true = 440.0
    sample_rate = 8000
    num_samples = 4000

    t = np.arange(num_samples) / sample_rate
    y_true = A_true * np.exp(-gamma_true * t) * np.sin(2 * np.pi * f_true * t)
    y_pred = A * np.exp(-gamma * t) * np.sin(2 * np.pi * f_val * t)

    mse = np.mean((y_true - y_pred)**2)

    print(f"MSE={mse}")
    if mse <= 1e-4:
        print("PASS")
        sys.exit(0)
    else:
        print("FAIL")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app

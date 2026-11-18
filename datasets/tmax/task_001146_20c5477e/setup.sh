#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-numpy python3-scipy gcc
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Generate telemetry.wav and ground truth
    python3 -c "
import numpy as np
import scipy.io.wavfile as wav
import os

np.random.seed(42)
sample_rate = 16000
duration_pulse = 0.1
duration_silence = 0.05
t_pulse = np.linspace(0, duration_pulse, int(sample_rate * duration_pulse), endpoint=False)
t_silence = np.zeros(int(sample_rate * duration_silence))

audio = []
ground_truth_peaks = []

for i in range(50):
    amp = np.random.uniform(0.1, 1.0)
    ground_truth_peaks.append(amp)
    pulse = amp * np.sin(2 * np.pi * 1000 * t_pulse)
    pulse += np.random.normal(0, 0.01, len(pulse))
    audio.extend(pulse)
    audio.extend(t_silence)

audio = np.array(audio, dtype=np.float32)
wav.write('/app/telemetry.wav', sample_rate, audio)

expected_energy = sum(p**2 for p in ground_truth_peaks)
with open('/tmp/ground_truth.txt', 'w') as f:
    f.write(str(expected_energy))
"

    # Write buggy compute.c
    cat << 'EOF' > /home/user/compute.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    FILE *f = fopen("parsed_data.txt", "r");
    if (!f) return 1;

    // BUG: Buffer overflow. Array size is 40, but there are 50 pulses.
    float values[40]; 
    int count = 0;
    while(fscanf(f, "%f", &values[count]) == 1) {
        count++;
    }
    fclose(f);

    float sum = 0;
    for(int i=0; i<count; i++) {
        sum += values[i] * values[i];
    }
    printf("%f\n", sum);
    return 0;
}
EOF

    # Write buggy extract.py
    cat << 'EOF' > /home/user/extract.py
import scipy.io.wavfile as wav
import numpy as np

rate, data = wav.read('/app/telemetry.wav')
# BUG: thresholding logic is flawed and ignores negative peaks
peaks = []
for i in range(0, len(data), 1000):
    chunk = data[i:i+1000]
    if np.max(chunk) > 0.5: # Misses lower amplitude pulses and negative peaks
        peaks.append(np.max(chunk))

with open('parsed_data.txt', 'w') as f:
    for p in peaks:
        f.write(f"{p}\n")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app /tmp/ground_truth.txt

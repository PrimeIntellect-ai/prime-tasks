#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak python3-numpy python3-matplotlib
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Create freqs.json
    cat << 'EOF' > /app/freqs.json
{
    "A": 440.0, "C": 466.16, "D": 493.88, "E": 523.25, "F": 554.37,
    "G": 587.33, "H": 622.25, "I": 659.25, "K": 698.46, "L": 739.99,
    "M": 783.99, "N": 830.61, "P": 880.0, "Q": 932.33, "R": 987.77,
    "S": 1046.5, "T": 1108.73, "V": 1174.66, "W": 1244.51, "Y": 1318.51
}
EOF

    # Create oracle.py
    cat << 'EOF' > /app/oracle.py
#!/usr/bin/env python3
import sys
import math
import json
import numpy as np

def kahan_sum(elements):
    sum_val = 0.0
    c = 0.0
    for e in elements:
        y = e - c
        t = sum_val + y
        c = (t - sum_val) - y
        sum_val = t
    return sum_val

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    seq = sys.argv[1]

    with open('/app/freqs.json', 'r') as f:
        freqs = json.load(f)

    signal = []
    for i in range(1024):
        t = i / 1023.0
        elements = [math.sin(2 * math.pi * freqs[aa] * t) for aa in seq]
        signal.append(kahan_sum(elements))

    fft_res = np.fft.rfft(signal)
    mags = np.abs(fft_res)
    print(np.max(mags))

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle.py

    # Generate lab_recording.wav
    cat << 'EOF' > /tmp/transcript.txt
Hello. The standard protein sonification code is giving non-reproducible spectral peaks due to floating point reduction order. Please write a script at /home/user/simulate.py. It should accept a raw amino acid string as the first command-line argument. For each time step i from 0 to 1023, calculate t = i / 1023.0. The signal at t is the sum of math.sin(2 * math.pi * freq * t) for each amino acid's frequency, using the mapping in /app/freqs.json. Crucially, you must use Kahan summation for the inner sum over the amino acids at each time step to ensure exact bit-level reproducibility. Once you have the 1024 signal values, apply numpy.fft.rfft to the array, compute the absolute magnitudes, and print the maximum magnitude using standard Python print. Also, generate a plot of the time-domain signal for the sequence 'MKTLLIL' and save it as /home/user/plot.png.
EOF
    espeak -f /tmp/transcript.txt -w /app/lab_recording.wav

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest numpy scipy Levenshtein

    mkdir -p /app
    cat << 'EOF' > /app/setup.py
import numpy as np
import scipy.io.wavfile as wav

np.random.seed(42)
sequence = "".join(np.random.choice(['A', 'C', 'G', 'T'], size=200))

# Write hidden truth
with open('/app/hidden_truth.fasta', 'w') as f:
    f.write(">sequence_1\n")
    # Wrap to 80 chars
    for i in range(0, len(sequence), 80):
        f.write(sequence[i:i+80] + "\n")

# Generate audio
sample_rate = 8000
duration_per_base = 0.1
t = np.linspace(0, duration_per_base, int(sample_rate * duration_per_base), endpoint=False)

freq_map = {'A': 440, 'C': 550, 'G': 660, 'T': 770}
audio = []

for base in sequence:
    freq = freq_map[base]
    # Add base signal
    wave = np.sin(2 * np.pi * freq * t)
    # Add noise
    noise = np.random.normal(0, 0.5, len(t))
    signal = wave + noise
    audio.append(signal)

audio = np.concatenate(audio)
# Normalize to 16-bit PCM
audio = np.int16(audio / np.max(np.abs(audio)) * 32767)

wav.write('/app/nanopore_signal.wav', sample_rate, audio)
EOF

    python3 /app/setup.py

    cat << 'EOF' > /app/verifier.py
import sys
import Levenshtein

def read_fasta(path):
    with open(path, 'r') as f:
        lines = f.readlines()
    seq = "".join(l.strip() for l in lines if not l.startswith('>'))
    return seq

try:
    truth = read_fasta('/app/hidden_truth.fasta')
    decoded = read_fasta('/home/user/decoded.fasta')

    dist = Levenshtein.distance(truth, decoded)
    max_len = max(len(truth), len(decoded))
    accuracy = (max_len - dist) / max_len if max_len > 0 else 0

    print(f"Accuracy: {accuracy:.4f}")
    if accuracy >= 0.95:
        sys.exit(0)
    else:
        sys.exit(1)
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

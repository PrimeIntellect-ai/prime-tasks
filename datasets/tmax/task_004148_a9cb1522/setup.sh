#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy matplotlib

    # Create directories
    mkdir -p /app/audio /app/ground_truth /app/data

    # Generate initial state data
    python3 -c "
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, filtfilt

os.makedirs('/app/audio', exist_ok=True)
os.makedirs('/app/ground_truth', exist_ok=True)
os.makedirs('/app/data', exist_ok=True)

# Generate synthetic nanopore/audio signal
fs = 8000
t = np.linspace(0, 2, 2 * fs, endpoint=False)
# Clean signal: combinations of low-frequency sines mimicking sequencer states
clean_signal = 5000 * np.sin(2 * np.pi * 300 * t) + 3000 * np.sin(2 * np.pi * 800 * t)
# Add high frequency noise
noise = 4000 * np.sin(2 * np.pi * 2500 * t) + 2000 * np.random.randn(len(t))
raw_signal = clean_signal + noise

# Convert to 16-bit PCM
raw_signal_int16 = np.int16(np.clip(raw_signal, -32768, 32767))
wavfile.write('/app/audio/raw_squiggle.wav', fs, raw_signal_int16)

# Generate Ground Truth Filtered Audio
b, a = butter(4, 1500 / (0.5 * fs), btype='low')
gt_filtered = filtfilt(b, a, raw_signal_int16)
gt_filtered_int16 = np.int16(np.clip(gt_filtered, -32768, 32767))
wavfile.write('/app/ground_truth/clean_squiggle.wav', fs, gt_filtered_int16)

# Generate Reference Genome and Candidate Primer
reference_seq = 'ACGT' * 10 + 'AC' + 'TGCAGTACTAGC' + 'GT' * 20
candidate_seq = 'TGCAGTACTAGC'

with open('/app/data/reference.fasta', 'w') as f:
    f.write('>ref1\n' + reference_seq + '\n')

with open('/app/data/candidate.txt', 'w') as f:
    f.write(candidate_seq + '\n')
"

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

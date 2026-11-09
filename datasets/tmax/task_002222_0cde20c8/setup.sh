#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libhdf5-dev gcc make
    pip3 install pytest h5py numpy opencv-python-headless

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/setup.py
import cv2
import numpy as np
import h5py
import os

# Generate video
out = cv2.VideoWriter('/app/calibration_timelapse.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (100, 100))
for i in range(50):
    frame = np.full((100, 100, 3), int(i*20/50), dtype=np.uint8)
    out.write(frame)
for i in range(10):
    frame = np.full((100, 100, 3), 20, dtype=np.uint8)
    out.write(frame)
out.release()

# Generate reference model
ref_probs = np.array([
    [0.1, 0.2, 0.3, 0.4],
    [0.4, 0.3, 0.2, 0.1],
    [0.25, 0.25, 0.25, 0.25],
    [0.3, 0.3, 0.2, 0.2]
], dtype=np.float64)

with h5py.File('/app/reference_model.h5', 'w') as f:
    f.create_dataset('/dinucleotide_probs', data=ref_probs)

# Generate FASTA
def generate_fasta(filename, probs):
    bases = ['A', 'C', 'G', 'T']
    with open(filename, 'w') as f:
        for i in range(50):
            f.write(f'>seq{i}\n')
            seq = np.random.choice(bases)
            for _ in range(999):
                prev_idx = bases.index(seq[-1])
                next_base = np.random.choice(bases, p=probs[prev_idx])
                seq += next_base
            f.write(seq + '\n')

generate_fasta('/app/corpus/clean/sample1.fasta', ref_probs)
generate_fasta('/app/corpus/clean/sample2.fasta', ref_probs)

evil_probs = np.array([
    [0.4, 0.3, 0.2, 0.1],
    [0.1, 0.2, 0.3, 0.4],
    [0.25, 0.25, 0.25, 0.25],
    [0.3, 0.3, 0.2, 0.2]
], dtype=np.float64)

generate_fasta('/app/corpus/evil/sample1.fasta', evil_probs)
generate_fasta('/app/corpus/evil/sample2.fasta', evil_probs)
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        espeak \
        libhdf5-dev \
        gcc \
        ffmpeg

    pip3 install pytest h5py numpy

    mkdir -p /app

    # Generate audio note
    espeak -w /app/lab_note.wav "Please use a uniform prior between one point zero and five point zero. The proposal standard deviation should be zero point five. Run the chain for one hundred thousand iterations and discard the first ten thousand as burn-in."

    # Generate HDF5 alignments
    cat << 'EOF' > /tmp/gen_h5.py
import h5py
import numpy as np

np.random.seed(42)
seqs = np.zeros((100, 50), dtype=int)
ts_left = 120
tv_left = 60

for i in range(1, 100):
    seqs[i] = seqs[i-1].copy()
    if ts_left > 0:
        seqs[i, 0] = 2 if seqs[i-1, 0] == 0 else 0
        ts_left -= 1
    elif tv_left > 0:
        seqs[i, 1] = 1 if seqs[i-1, 1] == 0 else 0
        tv_left -= 1

with h5py.File('/app/alignments.h5', 'w') as f:
    f.create_dataset('/sequences', data=seqs)
EOF

    python3 /tmp/gen_h5.py
    rm /tmp/gen_h5.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

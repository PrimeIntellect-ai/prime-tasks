#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libhdf5-dev libfftw3-dev
    pip3 install pytest h5py numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import h5py
import numpy as np

N = 1000
Fs = 1000.0
t = np.arange(N) / Fs

# Create a signal with a dominant frequency at 125 Hz
freq = 125.0
signal = np.sin(2 * np.pi * freq * t) + 0.1 * np.random.randn(N)

with h5py.File('/home/user/spectroscopy_data.h5', 'w') as f:
    f.create_dataset('signal', data=signal, dtype='float64')
    f.create_dataset('baseline_peak', data=np.array(125.0), dtype='float64')
EOF

    python3 /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

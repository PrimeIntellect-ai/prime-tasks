#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libhdf5-dev hdf5-tools python3-h5py hdf5-helpers
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/create_h5.py
import h5py
import numpy as np

# Create the spectrogram file
with h5py.File('/home/user/spectrogram.h5', 'w') as f:
    # 100 wavelengths, 50 time steps
    data = np.zeros((100, 50), dtype=np.float64)
    for i in range(100):
        for j in range(50):
            # Deterministic linear function: i + j * 0.5
            data[i, j] = i + j * 0.5
    f.create_dataset('signal', data=data, dtype='f8')
EOF

    python3 /tmp/create_h5.py

    chmod -R 777 /home/user

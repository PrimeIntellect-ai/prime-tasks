#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest h5py scikit-learn numpy

    mkdir -p /home/user/data
    python3 -c "
import h5py
import numpy as np

np.random.seed(42)
X = np.random.randn(1000, 100)

with h5py.File('/home/user/data/features.h5', 'w') as f:
    f.create_dataset('dataset', data=X)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

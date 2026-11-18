#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy h5py netCDF4

mkdir -p /home/user/project
cd /home/user/project

python3 -c "
import h5py, numpy as np
np.random.seed(42)
data = np.random.randn(10, 1024).astype(np.float64)
with h5py.File('data.h5', 'w') as f:
    f.create_dataset('spectra', data=data)
"

cat << 'EOF' > fit.py
import h5py
import numpy as np
import random
import math
import netCDF4 as nc

def compute_metric(spectra_array):
    fft_vals = np.abs(np.fft.rfft(spectra_array))

    indices = list(range(len(fft_vals)))
    random.shuffle(indices)

    total = 0.0
    for i in indices:
        val = fft_vals[i] * (1 if i % 2 == 0 else -1)
        total += val

    return total

def save_to_netcdf(input_h5, output_nc):
    # TODO: Implement this
    pass
EOF

cat << 'EOF' > test_fit.py
import numpy as np
import random
from fit import compute_metric

def test_metric_reproducibility():
    np.random.seed(123)
    test_array = np.random.randn(1024)

    # Run multiple times with different shuffle seeds
    random.seed(1)
    res1 = compute_metric(test_array)

    random.seed(2)
    res2 = compute_metric(test_array)

    # Because of strict testing, we want exact equality or extremely close up to fsum precision
    assert res1 == res2, f"Results differ: {res1} != {res2}"
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

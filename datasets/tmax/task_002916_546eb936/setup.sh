#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        libcfitsio-dev \
        libhdf5-dev \
        hdf5-tools \
        build-essential

    pip3 install pytest numpy astropy scipy h5py

    mkdir -p /home/user/data
    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/data/generate_data.py
import numpy as np
from astropy.io import fits
from scipy.optimize import fsolve

np.random.seed(123)
N = 100
M_vals = np.sort(np.random.uniform(0, 2*np.pi, N))
K_true = 50.0
e_true = 0.3

V_vals = np.zeros(N)
for i, M in enumerate(M_vals):
    # Solve Kepler's equation
    func = lambda E: E - e_true * np.sin(E) - M
    E_sol = fsolve(func, M)[0]
    V_vals[i] = K_true * np.cos(E_sol) + np.random.normal(0, 1.0) # Add noise

col1 = fits.Column(name='M', format='D', array=M_vals)
col2 = fits.Column(name='V', format='D', array=V_vals)
hdu = fits.BinTableHDU.from_columns([col1, col2])
hdu.writeto('/home/user/data/observations.fits', overwrite=True)
EOF

    python3 /home/user/data/generate_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data /home/user/workspace
    chmod -R 777 /home/user

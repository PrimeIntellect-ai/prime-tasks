#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest numpy astropy

    useradd -m -s /bin/bash user || true

    # Generate the initial FITS dataset
    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
from astropy.io import fits
import os

os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(42)

frequencies = [10, 50, 100, 200]
N = 1024

for i, freq in enumerate(frequencies):
    t = np.arange(N)
    # Signal + noise
    flux = np.sin(2 * np.pi * freq * t / N) + np.random.normal(0, 0.5, N)

    col = fits.Column(name='FLUX', format='D', array=flux)
    hdu = fits.BinTableHDU.from_columns([col])

    primary = fits.PrimaryHDU()
    hdul = fits.HDUList([primary, hdu])
    hdul.writeto(f'/home/user/data/sensor{i+1}.fits', overwrite=True)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user

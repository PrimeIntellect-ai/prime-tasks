#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup.py
import numpy as np
import pandas as pd

# Ground truth
C1 = 3.58257569
C2 = 1.85747218

wavelengths = np.linspace(400, 500, 1000)
sigma = 10.0
mu = 450.0

# Gaussian peaks where the integral is approximately the concentration
def gaussian(x, area, mu, sigma):
    return area / (sigma * np.sqrt(2 * np.pi)) * np.exp(-0.5 * ((x - mu) / sigma)**2)

int1 = gaussian(wavelengths, C1, mu, sigma)
int2 = gaussian(wavelengths, C2, mu, sigma)

df = pd.DataFrame({
    'Wavelength': wavelengths,
    'Intensity_1': int1,
    'Intensity_2': int2
})

df.to_csv('/home/user/spectra.csv', index=False)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user

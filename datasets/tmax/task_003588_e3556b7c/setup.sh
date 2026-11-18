#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas setuptools

    # Create the pyspectro package structure
    mkdir -p /app/pyspectro-1.0.0/pyspectro

    cat << 'EOF' > /app/pyspectro-1.0.0/setup.py
from setuptools import setup, find_packages
setup(
    name='pyspectro',
    version='1.0.0',
    packages=find_packages(),
    install_requires=['numpy' 'scipy'] # <--- Perturbation
)
EOF

    touch /app/pyspectro-1.0.0/pyspectro/__init__.py

    cat << 'EOF' > /app/pyspectro-1.0.0/pyspectro/voigt.py
import numpy as np
from scipy.optimize import curve_fit
from scipy.signal import find_peaks

def _multi_gauss(x, *params):
    y = np.zeros_like(x)
    for i in range(0, len(params), 3):
        ctr = params[i]
        amp = params[i+1]
        wid = params[i+2]
        y += amp * np.exp( -((x - ctr)/wid)**2 )
    return y

def fit_spectrum(x, y, num_peaks=3):
    """ Returns the centers of the peaks found in the spectrum. """
    peaks, _ = find_peaks(y, distance=50, prominence=2)
    if len(peaks) < num_peaks:
        # Fallback naive guess
        peaks = np.argsort(y)[-num_peaks:]

    guess = []
    for p in peaks[:num_peaks]:
        guess.extend([x[p], y[p], 5.0])

    try:
        popt, _ = curve_fit(_multi_gauss, x, y, p0=guess)
        centers = np.sort([popt[i] for i in range(0, len(popt), 3)])
        # Return tuple (centers, best_fit_y)
        return centers, _multi_gauss(x, *popt)
    except:
        return np.array([x[p] for p in peaks[:num_peaks]]), y
EOF

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate data
    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd
from scipy.signal import find_peaks

np.random.seed(42)
x = np.linspace(400, 700, 1000)
# True centers: 450.0, 520.5, 600.2
y = 10 * np.exp(-((x - 450.0) ** 2) / (2 * 5**2)) + \
    15 * np.exp(-((x - 520.5) ** 2) / (2 * 4**2)) + \
    8 * np.exp(-((x - 600.2) ** 2) / (2 * 6**2))

# Background baseline
baseline = 0.01 * (x - 400) + 2
y += baseline

# Noise
noise = np.random.normal(0, 1.5, size=x.shape)
y += noise

df = pd.DataFrame({'wavelength': x, 'intensity': y})
df.to_csv('/home/user/spectrum_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    # Set permissions
    chmod -R 777 /app
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest numpy pandas

    mkdir -p /home/user

    # Generate the spectra.csv dataset
    python3 -c "
import numpy as np
import pandas as pd

np.random.seed(42)
wavelengths = np.linspace(300, 600, 3001) # 0.1 nm resolution
# True peak at 452.0, width 15.0
intensities = 50.0 * np.exp(-0.5 * ((wavelengths - 452.0) / 15.0)**2) 
# Add background and noise
intensities += 10.0 + np.random.normal(0, 5.0, size=len(wavelengths))

df = pd.DataFrame({'wavelength': wavelengths, 'intensity': intensities})
df.to_csv('/home/user/spectra.csv', index=False)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

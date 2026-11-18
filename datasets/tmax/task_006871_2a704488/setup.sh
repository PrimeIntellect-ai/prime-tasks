#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy matplotlib

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/control
    mkdir -p /home/user/data/treatment

    cat << 'EOF' > /home/user/setup_data.py
import numpy as np
import os
import pandas as pd

np.random.seed(42)
wavenumber = np.linspace(400, 2000, 1601)

def make_spectrum(is_treatment):
    baseline = 0.005 * wavenumber
    noise = np.random.normal(0, 1.0, size=len(wavenumber))
    peak1 = 10 * np.exp(-((wavenumber - 500) / 10)**2)
    peak2_amp = 20 if is_treatment else 10
    peak2 = peak2_amp * np.exp(-((wavenumber - 1000) / 10)**2)
    peak3 = 10 * np.exp(-((wavenumber - 1500) / 10)**2)
    return baseline + noise + peak1 + peak2 + peak3

for i in range(10):
    df_c = pd.DataFrame({'wavenumber': wavenumber, 'intensity': make_spectrum(False)})
    df_c.to_csv(f'/home/user/data/control/sample_{i}.csv', index=False)

    df_t = pd.DataFrame({'wavenumber': wavenumber, 'intensity': make_spectrum(True)})
    df_t.to_csv(f'/home/user/data/treatment/sample_{i}.csv', index=False)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user

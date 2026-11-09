#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        libnetcdf-dev \
        tesseract-ocr \
        golang \
        imagemagick

    pip3 install pytest netCDF4 numpy

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate criteria.png
    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 20 -fill black \
        -draw "text 10,40 'Energy: E = 0.5*v^2 + 0.5*x^2.'" \
        -draw "text 10,80 'Calculate dE/dt using central difference: dE[i]/dt = (E[i+1] - E[i-1]) / (2*dt) for i=1 to N-2.'" \
        -draw "text 10,120 'Reject if max(|dE/dt|) > 0.001.'" \
        /app/criteria.png

    # Generate clean and evil datasets
    cat << 'EOF' > /tmp/generate.py
import os
import numpy as np
from netCDF4 import Dataset

N = 100
t = np.linspace(0, 10, N)
dt = t[1] - t[0]

# Clean files
for i in range(5):
    x = np.sin(t + i)
    v = np.cos(t + i)
    ds = Dataset(f'/app/corpus/clean/file_{i}.nc', 'w')
    ds.createDimension('dim', N)
    ds.createVariable('t', 'f8', ('dim',))[:] = t
    ds.createVariable('x', 'f8', ('dim',))[:] = x
    ds.createVariable('v', 'f8', ('dim',))[:] = v
    ds.close()

# Evil files
for i in range(5):
    x = np.sin(t + i)
    v = np.cos(t + i)
    # Add perturbation to v to create a spike in energy
    v[50] += 0.5
    ds = Dataset(f'/app/corpus/evil/file_{i}.nc', 'w')
    ds.createDimension('dim', N)
    ds.createVariable('t', 'f8', ('dim',))[:] = t
    ds.createVariable('x', 'f8', ('dim',))[:] = x
    ds.createVariable('v', 'f8', ('dim',))[:] = v
    ds.close()
EOF

    python3 /tmp/generate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

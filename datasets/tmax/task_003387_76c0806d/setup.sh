#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr libnetcdf-dev imagemagick fonts-dejavu-core
    pip3 install pytest netCDF4 numpy

    mkdir -p /app/corpus/clean /app/corpus/evil /app/sample_data

    # Create the image fixture
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 20 -fill black \
        -annotate +10+40 "Use statistical bounds." \
        -annotate +10+70 "REJECT_THRESHOLD = 3.82" \
        /app/glitch_criteria.png

    # Python script to generate NetCDF data
    cat << 'EOF' > /tmp/gen_data.py
import netCDF4 as nc
import numpy as np
import os

np.random.seed(42)

def create_nc(path, evil):
    ds = nc.Dataset(path, 'w', format='NETCDF4')
    ds.createDimension('time', 1000)
    sig = ds.createVariable('signal', 'f4', ('time',))

    # Generate N(0, 1.5) noise
    data = np.random.normal(0, 1.5, 1000)

    if evil:
        # Insert a spike that exceeds 3.82 * std
        std_dev = np.std(data, ddof=1)
        data[500] = (3.85 * std_dev) + np.mean(data)
    else:
        # Cap outliers to ensure clean data passes safely below 3.82
        std_dev = np.std(data, ddof=1)
        mean = np.mean(data)
        data = np.clip(data, mean - 3.5*std_dev, mean + 3.5*std_dev)

    sig[:] = data
    ds.close()

for i in range(50):
    create_nc(f'/app/corpus/clean/clean_{i}.nc', False)
    create_nc(f'/app/corpus/evil/evil_{i}.nc', True)

# Copy a few for the agent to inspect
os.system('cp /app/corpus/clean/clean_0.nc /app/sample_data/')
os.system('cp /app/corpus/evil/evil_0.nc /app/sample_data/')
EOF
    python3 /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

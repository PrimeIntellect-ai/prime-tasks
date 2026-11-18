#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libnetcdf-dev libfftw3-dev
    pip3 install pytest netCDF4 numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import numpy as np
import netCDF4 as nc

N = 4096
n = np.arange(N)
signal = 2.0 * np.sin(2 * np.pi * 1365 / N * n) + 1.0 * np.sin(2 * np.pi * 400 / N * n)

ds = nc.Dataset('/home/user/sequence_data.nc', 'w', format='NETCDF4')
ds.createDimension('time', N)
var = ds.createVariable('mapped_sequence', 'f8', ('time',))
var[:] = signal
ds.close()
EOF

    python3 /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

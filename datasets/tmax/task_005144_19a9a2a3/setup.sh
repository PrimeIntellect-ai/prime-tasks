#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-numpy python3-netcdf4
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/gen_data.py
import netCDF4 as nc
import numpy as np

# Create data
x = np.linspace(0.1, 10.0, 1000)
y = x * np.exp(-1.5 * x)

# Add tiny noise
np.random.seed(42)
y += np.abs(np.random.normal(0, 0.01, size=len(x)))

# Write to NetCDF
ds = nc.Dataset('/home/user/data.nc', 'w', format='NETCDF4')
ds.createDimension('dim', len(x))
x_var = ds.createVariable('x', 'f8', ('dim',))
y_var = ds.createVariable('y', 'f8', ('dim',))
x_var[:] = x
y_var[:] = y
ds.close()
EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    chmod -R 777 /home/user

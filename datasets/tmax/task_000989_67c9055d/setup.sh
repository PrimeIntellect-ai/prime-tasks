#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libnetcdf-dev golang
    pip3 install pytest netCDF4 numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_nc.py
import netCDF4 as nc
import numpy as np

ds = nc.Dataset('/home/user/climate_grid.nc', 'w', format='NETCDF4')
ds.createDimension('x', 50)
ds.createDimension('y', 50)

temp = ds.createVariable('temperature', 'f4', ('x', 'y'))

data = np.zeros((50, 50), dtype=np.float32)
for i in range(50):
    for j in range(50):
        data[i, j] = i + j

data[20:30, 20:30] = -999.0

temp[:] = data
ds.close()
EOF

    python3 /tmp/generate_nc.py
    rm /tmp/generate_nc.py

    chmod -R 777 /home/user

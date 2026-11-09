#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libnetcdf-dev
    pip3 install pytest numpy netCDF4

    mkdir -p /home/user

    python3 -c "
import netCDF4 as nc
import numpy as np

dataset = nc.Dataset('/home/user/input.nc', 'w', format='NETCDF4')
dim = dataset.createDimension('n', 100)
var = dataset.createVariable('coarse_data', 'f8', ('n',))
x = np.linspace(0, 10, 100)
var[:] = 5.0 + np.sin(x) + 0.5 * x
dataset.close()
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

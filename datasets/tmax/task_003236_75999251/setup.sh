#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy h5py netCDF4 scipy

    mkdir -p /home/user/data
    cd /home/user/data

    cat << 'EOF' > generate_data.py
import numpy as np
import h5py
import netCDF4 as nc

np.random.seed(42)

# Generate simulation data
sim_data = np.random.normal(loc=15.0, scale=3.0, size=(100, 100))

# Generate observational data (slightly correlated with noise)
noise = np.random.normal(loc=0.5, scale=1.5, size=(100, 100))
obs_data_100x100 = sim_data * 0.8 + 3.0 + noise

# Reshape obs data to 200x50
obs_data_200x50 = obs_data_100x100.reshape((200, 50))

# Save HDF5
with h5py.File('/home/user/data/sim_data.h5', 'w') as f:
    f.create_dataset('temperature_field', data=sim_data)

# Save NetCDF4
ds = nc.Dataset('/home/user/data/obs_data.nc', 'w', format='NETCDF4')
ds.createDimension('dim0', 200)
ds.createDimension('dim1', 50)
temp_var = ds.createVariable('temp_obs', 'f8', ('dim0', 'dim1'))
temp_var[:] = obs_data_200x50
ds.close()
EOF

    python3 generate_data.py
    rm generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

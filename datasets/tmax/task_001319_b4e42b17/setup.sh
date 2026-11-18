#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install Rust and HDF5 dependencies
    apt-get install -y cargo rustc libhdf5-dev python3-h5py python3-numpy

    # Create the user
    useradd -m -s /bin/bash user || true

    # Generate the HDF5 file
    python3 -c "
import h5py
import numpy as np
with h5py.File('/home/user/observation.h5', 'w') as f:
    x = np.array([1.0, 2.0, 3.0, 4.0, 5.0], dtype=np.float64)
    y = np.array([2.1, 3.9, 6.2, 8.1, 10.0], dtype=np.float64)
    f.create_dataset('x', data=x)
    f.create_dataset('y', data=y)
"

    # Set permissions
    chmod -R 777 /home/user

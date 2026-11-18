#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip hdf5-tools
pip3 install pytest h5py numpy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup_h5.py
import h5py
import numpy as np

src = np.array([1, 1, 1, 2, 3, 4, 4, 4, 4, 5])
tgt = np.array([2, 3, 4, 4, 4, 5, 6, 7, 8, 8])

with h5py.File('/home/user/network.h5', 'w') as f:
    f.create_dataset('/links/source', data=src)
    f.create_dataset('/links/target', data=tgt)
EOF
python3 /tmp/setup_h5.py
rm /tmp/setup_h5.py

chmod -R 777 /home/user

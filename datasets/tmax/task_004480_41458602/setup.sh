#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest h5py numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import h5py
import numpy as np

time = np.linspace(0, 10, 1000, endpoint=False) # dt = 0.01, fs = 100 Hz
np.random.seed(42)
# True slope = 0.42, True freq = 7.8
z_coord = 1.5 * np.sin(2 * np.pi * 7.8 * time) + 0.42 * time + 3.14 + np.random.normal(0, 0.05, 1000)

with h5py.File('/home/user/fluctuations.h5', 'w') as f:
    f.create_dataset('time', data=time)
    f.create_dataset('z_coord', data=z_coord)

pdb_content = """ATOM    144  N   TYR A  18      10.511  21.942  12.339  1.00 10.00           N  
ATOM    145  CA  TYR A  18      10.983  21.155  11.189  1.00 10.00           C  
ATOM    146  C   TYR A  18       9.882  20.250  10.669  1.00 10.00           C  
"""
with open('/home/user/structure.pdb', 'w') as f:
    f.write(pdb_content)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

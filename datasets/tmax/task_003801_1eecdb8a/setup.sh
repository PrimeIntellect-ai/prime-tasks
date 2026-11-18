#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip hdf5-tools time bc
pip3 install pytest h5py numpy

mkdir -p /home/user/data

cat << 'EOF' > /home/user/create_data.py
import h5py
import numpy as np

with h5py.File('/home/user/data/spectra.h5', 'w') as f:
    # 5000 elements
    data = np.random.rand(5000) * 100
    data[2500] = 999.9  # peak
    f.create_dataset('/spectroscopy/signal', data=data)
EOF

python3 /home/user/create_data.py
rm /home/user/create_data.py

cat << 'EOF' > /home/user/analyze_mesh.py
import sys
import h5py
import time
import numpy as np

if len(sys.argv) != 3:
    sys.exit(1)

filepath = sys.argv[1]
level = int(sys.argv[2])

with h5py.File(filepath, 'r') as f:
    data = f['/spectroscopy/signal'][:]

# Mock mesh refinement / density peak finding
peak = np.max(data) / level

# Simulate processing time based on level
time.sleep(0.05 * level)

print(f"{peak:.4f}")
EOF

chmod +x /home/user/analyze_mesh.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

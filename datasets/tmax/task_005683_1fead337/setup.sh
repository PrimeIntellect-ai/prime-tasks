#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy h5py

mkdir -p /home/user/ml_data

cat << 'EOF' > /home/user/process_v1.py
import sys
import h5py
import numpy as np

try:
    with h5py.File(sys.argv[1], 'r') as f:
        mat = f['matrix'][:]
        # v1 uses pseudo-inverse which is numerically stable for singular matrices
        res = np.linalg.pinv(mat)
    sys.exit(0)
except Exception:
    sys.exit(1)
EOF

cat << 'EOF' > /home/user/process_v2.py
import sys
import h5py
import numpy as np

try:
    with h5py.File(sys.argv[1], 'r') as f:
        mat = f['matrix'][:]
        # v2 uses standard inverse which fails on singular/near-singular matrices
        res = np.linalg.inv(mat)
    sys.exit(0)
except Exception:
    sys.exit(1)
EOF

chmod +x /home/user/process_v1.py
chmod +x /home/user/process_v2.py

cat << 'EOF' > /tmp/gen_data.py
import h5py
import numpy as np

def make_h5(name, mat):
    with h5py.File(name, 'w') as f:
        f.create_dataset('matrix', data=mat)

# data_01: well conditioned (v1 passes, v2 passes)
make_h5('/home/user/ml_data/data_01.h5', np.eye(3))

# data_02: singular (v1 passes, v2 fails)
make_h5('/home/user/ml_data/data_02.h5', np.ones((3,3)))

# data_03: singular (v1 passes, v2 fails)
make_h5('/home/user/ml_data/data_03.h5', np.array([[1.0, 2.0], [2.0, 4.0]]))

# data_04: well conditioned (v1 passes, v2 passes)
make_h5('/home/user/ml_data/data_04.h5', np.array([[2.0, 0.0], [0.0, 3.0]]))

# data_05: missing 'matrix' key, invalid data (v1 fails, v2 fails)
with h5py.File('/home/user/ml_data/data_05.h5', 'w') as f:
    f.create_dataset('other_data', data=np.eye(3))
EOF

python3 /tmp/gen_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

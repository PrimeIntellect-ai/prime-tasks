#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest numpy astropy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import json
import numpy as np
from astropy.io import fits

# 1. Create the data directory
os.makedirs('/home/user/data', exist_ok=True)

# 2. Generate a near-singular matrix
np.random.seed(42)
# Create a 5x5 matrix where the last column is almost identical to the 4th
A_base = np.random.rand(5, 5)
A_base[:, 4] = A_base[:, 3] + 1e-6
# Make it a symmetric positive semi-definite matrix
A = A_base.T @ A_base

# 3. Write to FITS file
hdu = fits.PrimaryHDU(A)
hdu.writeto('/home/user/data/matrix.fits', overwrite=True)

# 4. Calculate the expected ground-truth solution
lambda_reg = 0.05
A_prime = A + lambda_reg * np.eye(5)
b = np.ones(5)
x = np.linalg.solve(A_prime, b)

# Save ground truth for the verification script
with open('/home/user/expected_solution.json', 'w') as f:
    json.dump(x.tolist(), f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

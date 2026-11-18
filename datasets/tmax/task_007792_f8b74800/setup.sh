#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv
pip3 install pytest numpy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup_data.py
import csv
import numpy as np

np.random.seed(42)
with open('/home/user/raw_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['x', 'y', 'z'])
    for _ in range(500):
        # Generate roots such that there's 1 real root and 2 complex conjugate roots
        r = np.random.uniform(-10, 10)
        a = np.random.uniform(-5, 5)
        b = np.random.uniform(1, 5)
        # (w-r)(w-(a+bi))(w-(a-bi)) = (w-r)(w^2 - 2aw + a^2 + b^2)
        # = w^3 - (r+2a)w^2 + (2ar + a^2 + b^2)w - r(a^2 + b^2)
        x = -(r + 2*a)
        y = 2*a*r + a**2 + b**2
        z = -r*(a**2 + b**2)
        writer.writerow([x, y, z])
EOF
python3 /tmp/setup_data.py

chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np

np.random.seed(42)
wavelengths = np.linspace(200, 300, 50)
peaks = [260, 270, 250, 280]
widths = [15, 10, 20, 12]
A = np.zeros((50, 4))
for i in range(4):
    A[:, i] = np.exp(-((wavelengths - peaks[i])/widths[i])**2)

true_c = np.random.rand(4, 5)
B = A @ true_c + np.random.normal(0, 0.01, (50, 5))

np.savetxt('/home/user/pure_components.csv', A, delimiter=',')
np.savetxt('/home/user/spectra.csv', B, delimiter=',')
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user

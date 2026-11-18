#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy jupyter nbformat nbconvert ipykernel

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import nbformat as nbf

nb = nbf.v4.new_notebook()

code1 = """import numpy as np
import os
np.random.seed(42)
# Generate signals
t = np.linspace(0, 1, 100)
signals = np.sin(2 * np.pi * 10 * t) + 0.1 * np.random.randn(50, 100)
# FFT filter (low pass)
F = np.fft.fft(signals, axis=1)
F[:, 20:-20] = 0
filtered = np.real(np.fft.ifft(F, axis=1))
"""

code2 = """# Covariance matrix
C = np.cov(filtered)
"""

code3 = """# Cholesky decomposition
L = np.linalg.cholesky(C)
"""

code4 = """# Save trace
with open('/home/user/trace.txt', 'w') as f:
    f.write(str(np.trace(L)))
"""

nb['cells'] = [nbf.v4.new_code_cell(c) for c in [code1, code2, code3, code4]]
nbf.write(nb, '/home/user/simulation.ipynb')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

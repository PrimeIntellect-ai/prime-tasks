#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import numpy as np
import pandas as pd

np.random.seed(101)
x = np.linspace(0, 100, 150)
a1, x1, w1 = 12.0, 42.0, 4.0
a2, x2, w2 = 9.0, 58.0, 5.0
m, c = 0.02, 1.5

y = (a1 / (1 + ((x - x1)/w1)**2)) + (a2 / (1 + ((x - x2)/w2)**2)) + m*x + c
noise = np.random.normal(0, 0.5, size=len(x))
y_noisy = y + noise

df = pd.DataFrame({'wavelength': x, 'intensity': y_noisy})
df.to_csv('/home/user/spectroscopy_data.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user

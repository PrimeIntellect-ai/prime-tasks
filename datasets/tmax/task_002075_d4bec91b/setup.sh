#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick gsfonts
pip3 install pytest numpy scipy

mkdir -p /home/user/data
mkdir -p /home/user/results
mkdir -p /app

# Generate the calibration note image
convert -background white -fill black -pointsize 18 label:"To stabilize the spectroscopy inversion, apply Tikhonov regularization with lambda = 0.05.\nThe diagonal penalty weights matrix W for [k1, k2, A0] should be scaled as [1.0, 5.0, 0.1]." /app/calibration_note.png

# Generate the dataset
cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
from scipy.integrate import odeint
import csv

k1_true = 0.85
k2_true = 0.15
A0_true = 10.0

def system(y, t, k1, k2):
    A, B, C = y
    return [-k1*A, k1*A - k2*B, k2*B]

t = np.linspace(0, 20, 100)
y0 = [A0_true, 0, 0]
sol = odeint(system, y0, t, args=(k1_true, k2_true))

eps_A, eps_B, eps_C = 2.0, 1.0, 0.5
signal = eps_A * sol[:, 0] + eps_B * sol[:, 1] + eps_C * sol[:, 2]

np.random.seed(42)
noise = np.random.normal(0, 0.5, size=signal.shape)
noisy_signal = signal + noise

with open('/home/user/data/spectroscopy.csv', 'w') as f:
    writer = csv.writer(f)
    writer.writerow(['time', 'signal'])
    for ti, si in zip(t, noisy_signal):
        writer.writerow([ti, si])
EOF

python3 /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app

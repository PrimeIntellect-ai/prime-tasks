#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    # Generate the initial data file
    python3 -c '
import numpy as np
import os

np.random.seed(42)
t = np.linspace(0, 1, 100, endpoint=False)
# Ground truth parameters: f=7 Hz, A=3.2, phi=0.8
y_true = 3.2 * np.cos(2 * np.pi * 7 * t + 0.8)
y_noisy = y_true + np.random.normal(0, 0.5, size=len(t))

os.makedirs("/home/user", exist_ok=True)
with open("/home/user/signal.csv", "w") as f:
    f.write("t,y\n")
    for i in range(len(t)):
        f.write(f"{t[i]:.4f},{y_noisy[i]:.4f}\n")
'

    chmod -R 777 /home/user

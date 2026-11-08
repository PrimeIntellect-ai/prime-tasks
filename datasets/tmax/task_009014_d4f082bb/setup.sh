#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libfftw3-dev sudo
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    python3 -c '
import numpy as np
import os

np.random.seed(123)
# True parameters
A_true = 2.5
f_true = 3.0
phi_true = 1.2
sigma = 0.5

# Generate uneven x
N_points = 200
x_min, x_max = 0.0, 10.0
x = np.sort(np.random.uniform(x_min, x_max, N_points))
x[0] = x_min
x[-1] = x_max

# Generate y
y = A_true * np.sin(2 * np.pi * f_true * x + phi_true) + np.random.normal(0, sigma, N_points)

os.makedirs("/home/user", exist_ok=True)
with open("/home/user/raw_signal.csv", "w") as f:
    for xi, yi in zip(x, y):
        f.write(f"{xi},{yi}\n")
'

    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
from scipy.integrate import odeint
import csv

# True parameters
k_UI_true = 1.2
k_IU_true = 0.2
k_IB_true = 0.4
k_BI_true = 0.1

def model(y, t, k_UI, k_IU, k_IB, k_BI):
    U, I, B = y
    dUdt = -k_UI * U + k_IU * I
    dIdt = k_UI * U - (k_IU + k_IB) * I + k_BI * B
    dBdt = k_IB * I - k_BI * B
    return [dUdt, dIdt, dBdt]

t_points = np.linspace(0, 10, 50)
y0 = [1.0, 0.0, 0.0]

y_true = odeint(model, y0, t_points, args=(k_UI_true, k_IU_true, k_IB_true, k_BI_true))

np.random.seed(123)
noise = np.random.normal(0, 0.05, y_true.shape)
y_obs = y_true + noise

with open('/home/user/protein_kinetics.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['time', 'U', 'I', 'B'])
    for i in range(len(t_points)):
        writer.writerow([t_points[i], y_obs[i,0], y_obs[i,1], y_obs[i,2]])
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

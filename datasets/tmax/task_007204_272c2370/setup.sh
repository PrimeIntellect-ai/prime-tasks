#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy matplotlib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import os

x = np.arange(0, 100, 0.1)
P_raw = np.exp(-((x - 10.0)**2) / (2 * 2.0**2)) * 100 
Q_raw = np.exp(-((x - 11.5)**2) / (2 * 2.5**2)) * 80

os.makedirs("/home/user", exist_ok=True)
with open("/home/user/latency_data.txt", "w") as f:
    f.write(" ".join(f"{val:.6f}" for val in P_raw) + "\n")
    f.write(" ".join(f"{val:.6f}" for val in Q_raw) + "\n")

dx = 0.1
P_smooth = P_raw + 1e-9
Q_smooth = Q_raw + 1e-9

def trapz_integral(y, dx):
    return np.sum((y[:-1] + y[1:]) / 2.0) * dx

P_area = trapz_integral(P_smooth, dx)
Q_area = trapz_integral(Q_smooth, dx)

P_norm = P_smooth / P_area
Q_norm = Q_smooth / Q_area

kl_integrand = P_norm * np.log(P_norm / Q_norm)
kl_div = trapz_integral(kl_integrand, dx)

with open("/home/user/.expected_kl.txt", "w") as f:
    f.write(f"KL: {kl_div:.6f}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_data.py
import numpy as np
from scipy.integrate import solve_ivp

def model(t, P, k):
    return -k * P * (1 + np.sin(t))

res = solve_ivp(model, [0, 10], [100], args=(0.5,), t_eval=np.arange(11))
with open("/home/user/observed.txt", "w") as f:
    for t, y in zip(res.t, res.y[0]):
        # adding a tiny bit of noise
        np.random.seed(int(t))
        noise = np.random.normal(0, 0.5)
        f.write(f"{t:.1f}\t{y+noise:.4f}\n")
EOF
    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    cat << 'EOF' > /home/user/simulate.py
import sys
import numpy as np

if len(sys.argv) != 2:
    print("Usage: python simulate.py <k>")
    sys.exit(1)

k = float(sys.argv[1])
P = 100.0
t_end = 10

# BUG: step size is too large, causing divergence for higher k
dt = 1.0 

for t in range(t_end + 1):
    print(f"{t:.1f}\t{P:.4f}")
    # Euler step
    P = P + dt * (-k * P * (1 + np.sin(t)))
EOF
    chmod +x /home/user/simulate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

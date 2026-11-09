#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    # Create the reference data setup script
    cat << 'EOF' > /home/user/setup_reference.py
import numpy as np
import pandas as pd
from scipy.optimize import fsolve

def equations(vars, p1, p2):
    u, v = vars
    eq1 = u**2 + p1 * v - 10
    eq2 = p2 * u + v**2 - 10
    return [eq1, eq2]

p_vals = [1.0, 2.0, 3.0, 4.0, 5.0]
data = []

for p1 in p_vals:
    for p2 in p_vals:
        u_exact, v_exact = fsolve(equations, (3.0, 3.0), args=(p1, p2))
        # Add predefined noise
        u_ref = u_exact + 0.05
        v_ref = v_exact - 0.03
        data.append([p1, p2, u_ref, v_ref])

df = pd.DataFrame(data, columns=['p1', 'p2', 'u_ref', 'v_ref'])
df.to_csv('/home/user/reference_data.csv', index=False)
EOF

    python3 /home/user/setup_reference.py
    rm /home/user/setup_reference.py

    chmod -R 777 /home/user

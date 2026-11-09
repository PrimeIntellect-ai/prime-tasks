#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy scipy flask fastapi uvicorn

mkdir -p /app/vendored_bio_sim /app/data

cat << 'EOF' > /app/data/input.pdb
ATOM      1  N   ALA A   1      10.000  10.000  10.000  1.00  0.00           N
ATOM      2  CA  ALA A   1      11.500  10.000  10.000  1.00  0.00           C
ATOM      3  C   ALA A   1      12.000  11.500  10.000  1.00  0.00           C
ATOM      4  O   ALA A   1      11.500  12.500  10.000  1.00  0.00           O
EOF

cat << 'EOF' > /app/vendored_bio_sim/__init__.py
from .sim import run_simulation, parse_pdb_x_coords
EOF

cat << 'EOF' > /app/vendored_bio_sim/sim.py
import numpy as np
from scipy.integrate import solve_ivp

def parse_pdb_x_coords(filepath):
    x_coords = []
    with open(filepath, 'r') as f:
        for line in f:
            if line.startswith("ATOM"):
                x = float(line[30:38].strip())
                x_coords.append(x)
    return np.array(x_coords)

def _ode_system(t, x):
    # Non-linear ODE: dx/dt = -0.1 * x^3 + sin(t)
    return -0.1 * x**3 + np.sin(t)

def run_simulation(filepath):
    initial_x = parse_pdb_x_coords(filepath)
    t_span = (0, 10)

    # PERTURBATION: first_step=1000.0 is intentionally broken for this system
    sol = solve_ivp(_ode_system, t_span, initial_x, method='RK45', first_step=1000.0)

    if not sol.success:
        raise RuntimeError("Integration failed: " + sol.message)

    return initial_x, sol.y[:, -1]
EOF

chmod -R 755 /app

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

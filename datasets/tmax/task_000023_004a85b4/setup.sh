#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy networkx scipy

    mkdir -p /app/mol_sim/mol_sim

    cat << 'EOF' > /app/mol_sim/setup.py
from setuptools import setup, find_packages
setup(name='mol_sim', version='0.1.0', packages=find_packages(), install_requires=['numpy', 'networkx'])
EOF

    touch /app/mol_sim/mol_sim/__init__.py

    cat << 'EOF' > /app/mol_sim/mol_sim/integrator.py
import numpy as np

def adaptive_rk(func, t_span, y0, tol=1e-6):
    t0, tf = t_span
    t = t0
    y = np.array(y0, dtype=float)
    ts = [t]
    ys = [y.copy()]
    dt = 0.01

    while t < tf:
        if t + dt > tf:
            dt = tf - t

        # RK45 tableau simplified for mockup
        k1 = dt * func(t, y)
        k2 = dt * func(t + dt/2, y + k1/2)
        k3 = dt * func(t + dt/2, y + k2/2)
        k4 = dt * func(t + dt, y + k3)

        y_next = y + (k1 + 2*k2 + 2*k3 + k4) / 6

        # Fake error estimate for the sake of the scenario
        err = np.max(np.abs(k2 - k3)) + 1e-12

        # PERTURBATION HERE: wrong exponent
        dt_new = dt * min(2.0, max(0.1, (tol / err)**2))

        if err <= tol:
            t += dt
            y = y_next
            ts.append(t)
            ys.append(y.copy())

        dt = dt_new

    return np.array(ts), np.array(ys)
EOF

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/run_sim.py
import numpy as np
import networkx as nx
from mol_sim.integrator import adaptive_rk
import csv

# Fixed seed for reproducibility
np.random.seed(42)

# Generate graph
G = nx.erdos_renyi_graph(10, 0.3, seed=42)
L = nx.laplacian_matrix(G).toarray()

# Diffusion ODE
def diffusion(t, y):
    return -0.5 * L.dot(y)

# Initial conditions: node_0 has high concentration
y0 = np.zeros(10)
y0[0] = 10.0

# Run integration
t, y = adaptive_rk(diffusion, (0, 5.0), y0)

# Save output
with open('/home/user/sim_output.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    header = ['time'] + [f'node_{i}' for i in range(10)]
    writer.writerow(header)
    for i in range(len(t)):
        writer.writerow([t[i]] + list(y[i]))
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user

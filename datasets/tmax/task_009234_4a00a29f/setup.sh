#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    mkdir -p /home/user

    python3 -c '
import os
import numpy as np

os.makedirs("/home/user", exist_ok=True)

t_eval = np.linspace(0, 10, 500)
gamma_true, omega_true = 0.8, 7.5

def exact_solution(t, gamma, omega):
    if omega > gamma:
        omega_d = np.sqrt(omega**2 - gamma**2)
        return np.exp(-gamma*t) * (np.cos(omega_d*t) + (gamma/omega_d)*np.sin(omega_d*t))
    return np.zeros_like(t)

signal_true = exact_solution(t_eval, gamma_true, omega_true)
np.savetxt("/home/user/spectroscopy_data.csv", np.column_stack((t_eval, signal_true)), delimiter=",", header="time,signal", comments="")

starter_code = """import numpy as np
import pandas as pd

def simulate_phonon(gamma, omega, t_max, dt=0.5):
    # Buggy Euler Integrator
    times = np.arange(0, t_max, dt)
    x = np.zeros(len(times))
    v = np.zeros(len(times))
    x[0] = 1.0
    v[0] = 0.0

    for i in range(1, len(times)):
        a = -2 * gamma * v[i-1] - omega**2 * x[i-1]
        v[i] = v[i-1] + a * dt
        x[i] = x[i-1] + v[i-1] * dt

    return times, x

def cost_function(sim_signal, exp_signal):
    # Time-domain MSE (replace with FFT magnitude SSD)
    return np.sum((sim_signal - exp_signal)**2)

# Load data
data = pd.read_csv("/home/user/spectroscopy_data.csv")
t_exp = data["time"].values
sig_exp = data["signal"].values

# TODO: Fix integrator, implement FFT cost, and run 2000 Monte Carlo samples
# uniform gamma in [0.1, 2.0], uniform omega in [5.0, 10.0].
# Save to /home/user/best_params.json
"""

with open("/home/user/fit_phonon.py", "w") as f:
    f.write(starter_code)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

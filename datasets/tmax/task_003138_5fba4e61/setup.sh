#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy scipy

    # Create phys_fit package
    mkdir -p /app/phys_fit-1.2.0/phys_fit

    cat << 'EOF' > /app/phys_fit-1.2.0/setup.py
from setuptools import setup, find_packages
setup(
    name='phys_fit',
    version='1.2.0',
    packages=find_packages(),
    install_requires=[
        'numpy'
        'scipy'
    ]
)
EOF

    touch /app/phys_fit-1.2.0/phys_fit/__init__.py

    cat << 'EOF' > /app/phys_fit-1.2.0/phys_fit/oscillator.py
import numpy as np
from scipy.optimize import curve_fit

def fit_damped_curve(t, x):
    def model(t, A, gamma, omega, phi):
        return A * np.exp(-gamma * t) * np.cos(omega * t + phi)

    # Heuristic initial guesses
    A_guess = np.max(np.abs(x))
    gamma_guess = 0.1
    # Estimate frequency from zero crossings
    zero_crossings = np.where(np.diff(np.signbit(x)))[0]
    omega_guess = np.pi / (t[zero_crossings[1]] - t[zero_crossings[0]]) if len(zero_crossings) > 1 else 1.0

    try:
        popt, _ = curve_fit(model, t, x, p0=[A_guess, gamma_guess, omega_guess, 0.0], maxfev=2000)
    except:
        popt = [0, 0, 0, 0]

    return {'A': popt[0], 'gamma': popt[1], 'omega': popt[2], 'phi': popt[3]}
EOF

    # Generate corpora
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    python3 -c "
import numpy as np

t = np.linspace(0, 10, 100)

# Clean
for i in range(1, 6):
    A = 10.0
    gamma = 0.2 + 0.05 * i
    omega = 2.0 + 0.5 * i
    x = A * np.exp(-gamma * t) * np.cos(omega * t)
    with open(f'/app/corpora/clean/clean_0{i}.csv', 'w') as f:
        f.write('t,x\n')
        for tj, xj in zip(t, x):
            f.write(f'{tj},{xj}\n')

# Evil 1 & 2: negative gamma
for i in range(1, 3):
    A = 1.0
    gamma = -0.2
    omega = 2.0
    x = A * np.exp(-gamma * t) * np.cos(omega * t)
    with open(f'/app/corpora/evil/evil_0{i}.csv', 'w') as f:
        f.write('t,x\n')
        for tj, xj in zip(t, x):
            f.write(f'{tj},{xj}\n')

# Evil 3, 4, 5: spike
for i in range(3, 6):
    A = 10.0
    gamma = 0.3
    omega = 3.0
    x = A * np.exp(-gamma * t) * np.cos(omega * t)
    idx = np.argmin(np.abs(t - 5.0))
    x[idx] += 2.0
    with open(f'/app/corpora/evil/evil_0{i}.csv', 'w') as f:
        f.write('t,x\n')
        for tj, xj in zip(t, x):
            f.write(f'{tj},{xj}\n')
"

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

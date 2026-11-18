#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy h5py flask requests setuptools

    useradd -m -s /bin/bash user || true

    python3 -c '
import h5py
import numpy as np
with h5py.File("/home/user/initial_states.h5", "w") as f:
    f.create_dataset("state_0", data=np.array([1.0, 1.0, 0.0, 0.0], dtype=np.float64))
'

    mkdir -p /app/scipack-1.0.0/scipack

    cat << 'EOF' > /app/scipack-1.0.0/setup.py
from setuptools import setup, find_packages
setup(name='scipack', version='1.0.0', packages=find_packages())
EOF

    touch /app/scipack-1.0.0/scipack/__init__.py

    cat << 'EOF' > /app/scipack-1.0.0/scipack/ode.py
import numpy as np
def solve_ivp_adaptive(fun, t_span, y0, tol=1e-6, dt_init=0.01):
    t_start, t_end = t_span
    t = [t_start]
    y = [np.array(y0)]
    dt = dt_init

    t_curr = t_start
    y_curr = np.array(y0)

    while t_curr < t_end:
        if t_curr + dt > t_end:
            dt = t_end - t_curr

        # RK45-like embedded step (simplified Heun-Euler for demonstration, but let's use a dummy error metric)
        k1 = fun(t_curr, y_curr)
        k2 = fun(t_curr + dt, y_curr + dt * k1)

        y_next = y_curr + dt * 0.5 * (k1 + k2)
        y_euler = y_curr + dt * k1

        error = np.max(np.abs(y_next - y_euler)) + 1e-12

        if error < tol:
            t_curr += dt
            y_curr = y_next
            t.append(t_curr)
            y.append(y_curr)

        # BUG: inverted ratio
        dt = dt * (error / tol)**0.2 
        # Should be dt = dt * (tol / error)**0.2

        # safety bounds
        dt = np.clip(dt, 1e-6, 0.5)

    return np.array(t), np.array(y)
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app

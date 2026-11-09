#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/simulate.py
import numpy as np

def vdp_deriv(t, y, mu):
    return np.array([y[1], mu * (1 - y[0]**2) * y[1] - y[0]])

def adaptive_euler_heun(mu, t_end=600.0, dt0=0.1, tol=1e-3):
    t = 0.0
    y = np.array([2.0, 0.0])
    times = [t]
    states = [y]
    dt = dt0

    while t < t_end:
        if t + dt > t_end:
            dt = t_end - t

        k1 = vdp_deriv(t, y, mu)
        y_e = y + dt * k1
        k2 = vdp_deriv(t + dt, y_e, mu)
        y_h = y + (dt / 2.0) * (k1 + k2)

        # BUG: Incorrect error calculation
        error = np.sum(y_h - y_e)

        if error < tol:
            t += dt
            y = y_h
            times.append(t)
            states.append(y)
            dt = min(dt * 1.5, 0.5)
        else:
            dt = max(dt * 0.5, 1e-4)

    return np.array(times), np.array(states)
EOF

    chmod -R 777 /home/user

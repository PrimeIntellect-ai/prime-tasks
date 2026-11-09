#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas matplotlib

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
from scipy.integrate import solve_ivp
import pandas as pd

integrator_code = """import numpy as np

def rk4_step(f, t, y, h):
    k1 = f(t, y)
    k2 = f(t + h/2, y + h/2 * k1)
    k3 = f(t + h/2, y + h/2 * k2)
    k4 = f(t + h, y + h * k3)
    return y + h/6 * (k1 + 2*k2 + 2*k3 + k4)

def adaptive_integrate(f, t0, y0, t_end, tol=1e-5):
    t = t0
    y = np.array(y0, dtype=float)
    h = 0.1

    times = [t]
    states = [y]

    while t < t_end:
        if t + h > t_end:
            h = t_end - t

        y1 = rk4_step(f, t, y, h)

        y_half = rk4_step(f, t, y, h/2)
        y2 = rk4_step(f, t + h/2, y_half, h/2)

        error = np.linalg.norm(y2 - y1) + 1e-15

        # BUG: inverted ratio and missing safety factor
        h_new = h * (error / tol)**0.2

        if error <= tol:
            t += h
            y = y2
            times.append(t)
            states.append(y)

        h = max(1e-5, min(h_new, 1.0))

        if len(times) > 10000:
            raise RuntimeError("Integration diverged or took too many steps.")

    return np.array(times), np.array(states)

def vdp_deriv(t, y):
    mu = 1.5
    return np.array([y[1], mu*(1 - y[0]**2)*y[1] - y[0]])
"""

with open("/home/user/integrator.py", "w") as f:
    f.write(integrator_code)

def vdp(t, y):
    mu = 1.5
    return [y[1], mu*(1 - y[0]**2)*y[1] - y[0]]

np.random.seed(42)
sol = solve_ivp(vdp, [0, 20], [2.0, 0.0], method='RK45', rtol=1e-8, atol=1e-8, dense_output=True)
t_obs = np.sort(np.random.uniform(0.1, 19.9, 50))
y_obs = sol.sol(t_obs)

df = pd.DataFrame({
    't': t_obs,
    'y0': y_obs[0] + np.random.normal(0, 0.01, len(t_obs)),
    'y1': y_obs[1] + np.random.normal(0, 0.01, len(t_obs))
})
df.to_csv("/home/user/obs_data.csv", index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

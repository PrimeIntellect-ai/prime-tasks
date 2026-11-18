#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/stiff_model.py
import numpy as np
import json
from scipy.integrate import solve_ivp

# Robertson's chemical reaction system
def robertson_ode(t, y):
    y1, y2, y3 = y
    dy1_dt = -0.04 * y1 + 1e4 * y2 * y3
    dy2_dt = 0.04 * y1 - 1e4 * y2 * y3 - 3e7 * y2**2
    dy3_dt = 3e7 * y2**2
    return [dy1_dt, dy2_dt, dy3_dt]

y0 = [1.0, 0.0, 0.0]
t_span = (0, 1e5)

# This explicit method will diverge or take excessively long due to wrong step-size adaptation for stiff problems.
# TODO: Fix the solver method to 'BDF', rtol=1e-6, atol=1e-10
sol = solve_ivp(robertson_ode, t_span, y0, method='RK45')

if sol.success:
    final_state = {
        "y1_final": float(sol.y[0, -1]),
        "y2_final": float(sol.y[1, -1]),
        "y3_final": float(sol.y[2, -1])
    }
    with open('/home/user/results.json', 'w') as f:
        json.dump(final_state, f, indent=2)
else:
    print("Integration failed!")
EOF
    chmod 644 /home/user/stiff_model.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

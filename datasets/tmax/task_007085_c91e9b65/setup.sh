#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy pandas

    mkdir -p /home/user/src /home/user/data

    cat << 'EOF' > /home/user/src/integrator.c
#include <math.h>

void rk4_step(double *x, double *v, double dt) {
    double x1 = *x, v1 = *v;
    double a1 = -sin(x1) - 0.2 * v1;

    double x2 = *x + 0.5 * dt * v1, v2 = *v + 0.5 * dt * a1;
    double a2 = -sin(x2) - 0.2 * v2;

    double x3 = *x + 0.5 * dt * v2, v3 = *v + 0.5 * dt * a2;
    double a3 = -sin(x3) - 0.2 * v3;

    double x4 = *x + dt * v3, v4 = *v + dt * a3;
    double a4 = -sin(x4) - 0.2 * v4;

    *x += (dt / 6.0) * (v1 + 2*v2 + 2*v3 + v4);
    *v += (dt / 6.0) * (a1 + 2*a2 + 2*a3 + a4);
}

void integrate(double x0, double v0, double dt, int steps, double* out_x, double* out_v) {
    double x = x0;
    double v = v0;
    for (int i = 0; i < steps; i++) {
        out_x[i] = x;
        out_v[i] = v;
        rk4_step(&x, &v, dt);
    }
}
EOF

    # Compile temporarily to generate the golden dataset
    gcc -shared -o /home/user/src/libintegrator.so -fPIC /home/user/src/integrator.c -lm

    cat << 'EOF' > /tmp/generate_golden.py
import ctypes
import numpy as np
import pandas as pd

lib = ctypes.CDLL('/home/user/src/libintegrator.so')
lib.integrate.argtypes = [ctypes.c_double, ctypes.c_double, ctypes.c_double, ctypes.c_int, np.ctypeslib.ndpointer(dtype=np.float64), np.ctypeslib.ndpointer(dtype=np.float64)]

steps = 1000
dt = 0.05
out_x = np.zeros(steps, dtype=np.float64)
out_v = np.zeros(steps, dtype=np.float64)

lib.integrate(3.0, 0.0, dt, steps, out_x, out_v)

# Generate golden acceleration
out_a = np.gradient(out_v, dt, edge_order=2)

# Introduce a tiny perturbation to simulate cross-version differences for regression testing
# so MSE is small but non-zero.
np.random.seed(42)
out_x_golden = out_x + np.random.normal(0, 1e-5, steps)
out_v_golden = out_v + np.random.normal(0, 1e-5, steps)
out_a_golden = out_a + np.random.normal(0, 1e-5, steps)

df = pd.DataFrame({'x': out_x_golden, 'v': out_v_golden, 'a': out_a_golden})
df.to_csv('/home/user/data/golden_trajectory.csv', index=False)
EOF

    python3 /tmp/generate_golden.py
    rm /tmp/generate_golden.py
    rm /home/user/src/libintegrator.so

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

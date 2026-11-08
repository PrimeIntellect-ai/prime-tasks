#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > simulator.c
#include <stdio.h>
#include <math.h>
#include <stdlib.h>

#define TOL 1e-4
#define T_END 1.0
#define DT_MIN 1e-6
#define DT_MAX 0.1

// ODE System:
// dx/dt = -x
// dy/dt = 50 * (x - y)
void deriv(double t, double x, double y, double *dxdt, double *dydt) {
    *dxdt = -x;
    *dydt = 50.0 * (x - y);
}

int main() {
    double t = 0.0;
    double x = 1.0;
    double y = 0.0;
    double dt = 0.01;

    FILE *f = fopen("/home/user/output.txt", "w");
    if (!f) return 1;

    double next_print_t = 0.1;

    while (t < T_END) {
        if (t + dt > next_print_t && t < next_print_t) {
            dt = next_print_t - t;
        }

        double k1x, k1y, k2x, k2y;
        deriv(t, x, y, &k1x, &k1y);

        // Euler step
        double x_e = x + dt * k1x;
        double y_e = y + dt * k1y;

        // Heun step for error estimation
        deriv(t + dt, x_e, y_e, &k2x, &k2y);
        double x_h = x + dt * 0.5 * (k1x + k2x);
        double y_h = y + dt * 0.5 * (k1y + k2y);

        double err_x = fabs(x_h - x_e);
        double err_y = fabs(y_h - y_e);
        double err = (err_x > err_y) ? err_x : err_y;

        // BUGGY ADAPTATION LOGIC:
        if (err > TOL) {
            // Error is large, but we accidentally increase dt!
            dt = fmin(dt * 1.5, DT_MAX);
            x = x_h;
            y = y_h;
            t += dt;
        } else {
            // Error is small, but we accidentally decrease dt!
            dt = fmax(dt * 0.5, DT_MIN);
            x = x_h;
            y = y_h;
            t += dt;
        }

        if (t >= next_print_t - 1e-9) {
            fprintf(f, "%.6f\n", y);
            next_print_t += 0.1;
        }
    }
    fclose(f);
    return 0;
}
EOF

    cat << 'EOF' > ref_data.txt
0.812678
0.835439
0.755928
0.684033
0.618933
0.560032
0.506740
0.458525
0.414902
0.375422
EOF

    cat << 'EOF' > evaluate.py
import sys
import numpy as np

def kl_divergence(p, q):
    p = np.asarray(p, dtype=float) + 1e-10
    q = np.asarray(q, dtype=float) + 1e-10
    p /= p.sum()
    q /= q.sum()
    return np.sum(np.where(p != 0, p * np.log(p / q), 0))

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(1)

    try:
        data_out = np.loadtxt(sys.argv[1])
        data_ref = np.loadtxt(sys.argv[2])
    except Exception as e:
        print("Error reading files")
        sys.exit(1)

    if len(data_out) != len(data_ref):
        print("Length mismatch")
        sys.exit(1)

    kl = kl_divergence(data_out, data_ref)
    print(f"{kl:.6e}")
EOF

    chmod +x evaluate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

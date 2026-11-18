#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

cpp_code = """#include <iostream>
#include <vector>
#include <fstream>
#include <cmath>
#include <algorithm>

int main() {
    int nx = 50;
    int ny = 50;
    double L = 1.0;
    double dx = L / (nx - 1);
    double dy = L / (ny - 1);
    double alpha = 1.0;

    // BUG: Hardcoded dt that causes divergence on refined mesh
    double dt = 0.001; 

    double t_final = 0.05;
    int n_steps = std::ceil(t_final / dt);

    // Recalculate exact dt to hit t_final (if CFL was respected)
    dt = t_final / n_steps;

    std::vector<double> u(nx * ny, 0.0);
    std::vector<double> u_new(nx * ny, 0.0);

    // Initial condition: Hot spot in the middle
    for (int i = 0; i < nx; ++i) {
        for (int j = 0; j < ny; ++j) {
            double x = i * dx - 0.5;
            double y = j * dy - 0.5;
            if (x*x + y*y < 0.05) {
                u[i * ny + j] = 1.0;
            }
        }
    }

    for (int step = 0; step < n_steps; ++step) {
        for (int i = 1; i < nx - 1; ++i) {
            for (int j = 1; j < ny - 1; ++j) {
                int idx = i * ny + j;
                double d2udx2 = (u[(i + 1) * ny + j] - 2.0 * u[idx] + u[(i - 1) * ny + j]) / (dx * dx);
                double d2udy2 = (u[i * ny + (j + 1)] - 2.0 * u[idx] + u[i * ny + (j - 1)]) / (dy * dy);
                u_new[idx] = u[idx] + alpha * dt * (d2udx2 + d2udy2);
            }
        }
        u = u_new;
    }

    std::ofstream out("output.csv");
    for (int i = 0; i < nx * ny; ++i) {
        out << u[i] << "\\n";
    }
    out.close();

    return 0;
}
"""

with open("/home/user/heat_sim.cpp", "w") as f:
    f.write(cpp_code)

nx = 50
ny = 50
L = 1.0
dx = L / (nx - 1)
dy = L / (ny - 1)
alpha = 1.0
dt = 0.2 * min(dx * dx, dy * dy) / alpha
t_final = 0.05
n_steps = int(np.ceil(t_final / dt))
dt = t_final / n_steps

u = np.zeros((nx, ny))
for i in range(nx):
    for j in range(ny):
        x = i * dx - 0.5
        y = j * dy - 0.5
        if x*x + y*y < 0.05:
            u[i, j] = 1.0

np.random.seed(123)
reference_u = np.copy(u)
for step in range(n_steps):
    u_new = np.copy(reference_u)
    u_new[1:-1, 1:-1] = reference_u[1:-1, 1:-1] + alpha * dt * (
        (reference_u[2:, 1:-1] - 2 * reference_u[1:-1, 1:-1] + reference_u[:-2, 1:-1]) / (dx * dx) +
        (reference_u[1:-1, 2:] - 2 * reference_u[1:-1, 1:-1] + reference_u[1:-1, :-2]) / (dy * dy)
    )
    reference_u = u_new

reference_u += np.random.normal(0, 1e-4, (nx, ny))

with open("/home/user/reference.csv", "w") as f:
    for val in reference_u.flatten():
        f.write(f"{val}\n")
EOF

    python3 /tmp/setup.py

    chmod -R 777 /home/user

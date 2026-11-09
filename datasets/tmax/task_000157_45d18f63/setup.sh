#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/molecule.pdb
HEADER    DIATOMIC MOLECULE                       
ATOM      1  O   MOL A   1       0.000   0.000   0.000  1.00  0.00           O  
ATOM      2  O   MOL A   2       3.000   4.000   0.000  1.00  0.00           O  
END
EOF

    cat << 'EOF' > /home/user/simulate.cpp
#include <iostream>
#include <cmath>
#include <iomanip>

double f(double x) {
    return -std::pow(x - 2.0, 3.0);
}

void adaptive_euler_step(double& x, double& t, double& dt) {
    double x_full = x + dt * f(x);
    double x_half = x + (dt/2.0) * f(x);
    double x_two_halves = x_half + (dt/2.0) * f(x_half);

    double error = std::abs(x_full - x_two_halves);
    double tol = 1e-4;

    // BUGGY ADAPTIVE LOGIC
    if (error > tol) {
        dt *= 1.5;
    } else {
        dt *= 0.5;
    }

    if (dt > 0.1) dt = 0.1;
    if (dt < 1e-5) dt = 1e-5;

    x = x_two_halves;
    t += dt;
}

int main() {
    double x = 0.0; // Agent needs to change this to 5.0 (distance between 0,0,0 and 3,4,0)
    double t = 0.0;
    double dt = 0.01;
    double t_end = 10.0;

    while (t < t_end) {
        if (t + dt > t_end) {
            dt = t_end - t;
        }
        adaptive_euler_step(x, t, dt);
    }

    std::cout << std::fixed << std::setprecision(6) << x << std::endl;
    return 0;
}
EOF

    chmod -R 777 /home/user

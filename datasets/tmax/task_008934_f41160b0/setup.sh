#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required system packages
    apt-get install -y g++ libtbb-dev

    # Create the user and home directory structure
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/sim

    # Create the C++ simulation script
    cat << 'EOF' > /home/user/sim/equilibrium_sim.cpp
#include <iostream>
#include <vector>
#include <numeric>
#include <cmath>
#include <execution>
#include <iomanip>

int main() {
    int N = 5000000;
    std::vector<double> w(N);
    std::vector<double> t(N);
    for(int i=0; i<N; ++i) {
        w[i] = 1.0 + (i % 100) / 100.0;
        t[i] = 0.01 + (i % 50) / 500.0;
    }

    double x = 1.0; // Initial temperature guess
    double C = 2500000.0; // Target density

    // Newton Raphson nonlinear solver
    for(int iter=0; iter<15; ++iter) {
        double f_val = std::transform_reduce(std::execution::par,
            w.begin(), w.end(), t.begin(), 0.0,
            std::plus<>(),
            [x](double wi, double ti) { return wi * std::exp(-x * ti); }
        ) - C;

        double f_prime = std::transform_reduce(std::execution::par,
            w.begin(), w.end(), t.begin(), 0.0,
            std::plus<>(),
            [x](double wi, double ti) { return -wi * ti * std::exp(-x * ti); }
        );

        x = x - f_val / f_prime;
    }

    std::cout << std::fixed << std::setprecision(10) << x << std::endl;
    return 0;
}
EOF

    # Fix permissions
    chown -R user:user /home/user/sim
    chmod -R 777 /home/user

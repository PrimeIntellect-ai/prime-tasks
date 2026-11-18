#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sim.cpp
#include <iostream>
#include <vector>
#include <cmath>
#include <omp.h>
#include <iomanip>

int main(int argc, char** argv) {
    double dt = 0.1;
    if (argc > 1) dt = std::stod(argv[1]);

    double T = 10.0;
    int N = T / dt;
    std::vector<double> P(N);
    P[0] = 1.0; // initial primer concentration
    double k = 0.5;

    // ODE numerical solve (Euler)
    for(int i=0; i<N-1; ++i) {
        double t = i * dt;
        double dP = -k * P[i] + std::sin(2.0 * M_PI * t);
        P[i+1] = P[i] + dP * dt;
    }

    double total_energy = 0.0;

    // DFT and Spectral Energy
    #pragma omp parallel for
    for(int k_freq=0; k_freq<N; ++k_freq) {
        double re = 0.0;
        double im = 0.0;
        for(int n=0; n<N; ++n) {
            double angle = 2.0 * M_PI * k_freq * n / N;
            re += P[n] * std::cos(angle);
            im -= P[n] * std::sin(angle);
        }
        double energy = re*re + im*im;

        #pragma omp atomic
        total_energy += energy;
    }

    std::cout << std::fixed << std::setprecision(10);
    std::cout << P[N-1] << "," << total_energy << std::endl;
    return 0;
}
EOF

    chmod -R 777 /home/user

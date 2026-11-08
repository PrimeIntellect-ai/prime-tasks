#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy scipy

    mkdir -p /home/user/sim
    cat << 'EOF' > /home/user/sim/simulation.cpp
#include <iostream>
#include <vector>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <omp.h>

int main() {
    const int N = 10000;
    std::vector<double> signal(N, 0.0);
    double global_sum = 0.0;

    // Generate a signal with a dominant frequency of 50 Hz, sampled at 1000 Hz.
    #pragma omp parallel for
    for (int i = 0; i < N; ++i) {
        double t = i / 1000.0;
        // Deterministic pseudo-random noise
        double noise = ( (i * 1103515245 + 12345) % 10000 ) / 10000.0 - 0.5;
        double val = std::sin(2 * M_PI * 50 * t) + 0.5 * std::sin(2 * M_PI * 120 * t) + noise;
        signal[i] = val;
        global_sum += val; // BUG: Race condition here
    }

    std::ofstream out("signal.txt");
    for (int i = 0; i < N; ++i) {
        out << std::fixed << std::setprecision(6) << signal[i] << "\n";
    }

    std::ofstream sout("sum.txt");
    sout << std::fixed << std::setprecision(6) << global_sum << "\n";

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

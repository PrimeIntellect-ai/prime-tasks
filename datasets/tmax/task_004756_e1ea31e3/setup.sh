#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest
    apt-get install -y g++ libhdf5-dev
    pip3 install h5py numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mc_sim.cpp
#include <iostream>
#include <cmath>
#include <cstdlib>
#include <iomanip>
#include <omp.h>

// Simulates computationally expensive energy evaluation
double compute_energy(int i, int seed) {
    double x = (i * 137.0 + seed) * 0.01;
    return std::sin(x) * std::cos(x * 2.5);
}

int main(int argc, char** argv) {
    if (argc != 3) {
        std::cerr << "Usage: " << argv[0] << " <N> <seed>" << std::endl;
        return 1;
    }

    int N = std::atoi(argv[1]);
    int seed = std::atoi(argv[2]);

    double total_energy = 0.0;

    #pragma omp parallel for
    for(int i = 0; i < N; i++) {
        double e = compute_energy(i, seed);
        // Bug: Non-deterministic floating point addition order
        #pragma omp atomic
        total_energy += e;
    }

    std::cout << std::setprecision(15) << total_energy << std::endl;
    return 0;
}
EOF

    chmod -R 777 /home/user

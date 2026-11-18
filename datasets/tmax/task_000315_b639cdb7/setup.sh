#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/target.fasta
>target_sequence_1
ATGCGTAACGTAGCTAGCTAGGGAAATTTCCCGGGAAATTT
EOF

    cat << 'EOF' > /home/user/pcr_sim.cpp
#include <iostream>
#include <vector>
#include <cmath>
#include <omp.h>
#include <iomanip>
#include <string>

// Simulates the ODE for a single droplet
double simulate_droplet(double initial_gc, int steps) {
    double c = 0.1;
    for(int i=0; i<steps; ++i) {
        c += 0.05 * c * (1.0 - c) * initial_gc;
    }
    return c;
}

int main(int argc, char** argv) {
    if(argc != 2) {
        std::cerr << "Usage: ./pcr_sim <GC_ratio>\n";
        return 1;
    }

    double gc_ratio = std::stod(argv[1]);
    int num_droplets = 100000;
    double total_concentration = 0.0;

    // The atomic operation causes floating point non-determinism
    #pragma omp parallel for
    for(int i = 0; i < num_droplets; ++i) {
        double val = simulate_droplet(gc_ratio, 100);

        #pragma omp atomic
        total_concentration += val;
    }

    double expected = 50000.0;
    double distance = std::abs(total_concentration - expected);

    std::cout << std::fixed << std::setprecision(10) << distance << "\n";
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

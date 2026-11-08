#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mc_sim.cpp
#include <iostream>
#include <vector>

const int N = 8000;
std::vector<std::vector<double>> data;

double calculate_energy() {
    double sum = 0;
    // Cache-thrashing column-major traversal
    for (int j = 0; j < N; ++j) {
        for (int i = 0; i < N; ++i) {
            sum += data[i][j];
        }
    }
    return sum;
}

int main() {
    // Initialize array
    data.resize(N, std::vector<double>(N, 0.5));

    double total_energy = 0;
    // Simulate Monte Carlo steps
    for(int step = 0; step < 10; ++step) {
        total_energy += calculate_energy();
    }

    std::cout << (long long)total_energy << std::endl;
    return 0;
}
EOF

    chmod -R 777 /home/user

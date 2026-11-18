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
#include <cstdlib>
#include <iomanip>
#include <omp.h>

int main(int argc, char** argv) {
    if (argc != 2) {
        std::cerr << "Usage: ./sim <seed>\n";
        return 1;
    }
    int seed = std::atoi(argv[1]);
    std::srand(seed);

    int N = 10000;
    std::vector<double> data(N);
    for (int i = 0; i < N; ++i) {
        data[i] = (std::rand() % 1000) / 100.0;
    }

    double x = 0.0; // Initial guess
    double learning_rate = 0.01;

    // Optimization loop (gradient descent to find mean)
    for (int iter = 0; iter < 100; ++iter) {
        double gradient = 0.0;

        #pragma omp parallel for
        for (int i = 0; i < N; ++i) {
            double diff = x - data[i];
            #pragma omp atomic
            gradient += diff;
        }

        gradient /= N;
        x = x - learning_rate * gradient;
    }

    std::cout << std::fixed << std::setprecision(6) << x << std::endl;
    return 0;
}
EOF

    chmod -R 777 /home/user

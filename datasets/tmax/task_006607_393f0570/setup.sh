#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy

    mkdir -p /home/user/sim

    cat << 'EOF' > /home/user/sim/solver.cpp
#include <iostream>
#include <vector>
#include <cmath>
#include <random>
#include <string>

int main(int argc, char** argv) {
    int seed = 0;
    if (argc == 3 && std::string(argv[1]) == "--seed") {
        seed = std::stoi(argv[2]);
    } else {
        std::cerr << "Usage: " << argv[0] << " --seed <N>\n";
        return 1;
    }

    // Near-singular matrix A:
    // [ 1.0       1.0 ]
    // [ 1.0    1.0001 ]
    // Inverse A_inv:
    // [  10000   -10000 ]
    // [ -10000    10000 ] (approx)

    // True b = [2.0, 2.0001]^T => True x = [1.0, 1.0]^T

    std::mt19937 gen(seed);
    std::normal_distribution<double> noise(0.0, 0.001); // 0.001 stddev noise

    double b0 = 2.0 + noise(gen);
    double b1 = 2.0001 + noise(gen);

    // Explicit inverse multiplication
    double det = 1.0 * 1.0001 - 1.0 * 1.0;
    double inv00 = 1.0001 / det;
    double inv01 = -1.0 / det;
    double inv10 = -1.0 / det;
    double inv11 = 1.0 / det;

    double x0 = inv00 * b0 + inv01 * b1;
    double x1 = inv10 * b0 + inv11 * b1;

    double norm = std::sqrt(x0*x0 + x1*x1);

    // Print with high precision
    std::printf("%.8f\n", norm);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy scipy matplotlib pandas

    mkdir -p /home/user
    cat << 'EOF' > /home/user/pi_sim.cpp
#include <iostream>
#include <omp.h>
#include <chrono>
#include <iomanip>

int main() {
    long num_steps = 50000000;
    double step = 1.0 / (double)num_steps;
    double sum = 0.0;

    auto start = std::chrono::high_resolution_clock::now();

    #pragma omp parallel for
    for (long i = 0; i < num_steps; i++) {
        double x = (i + 0.5) * step;
        #pragma omp atomic
        sum += 4.0 / (1.0 + x * x);
    }

    double pi = step * sum;
    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double, std::milli> duration = end - start;

    std::cout << std::setprecision(10) << "Pi: " << pi << ", Time: " << duration.count() << "\n";
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user

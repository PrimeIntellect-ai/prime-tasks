#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy scipy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sim.cpp
#include <iostream>
#include <vector>
#include <chrono>
#include <cmath>
#include <iomanip>

int main() {
    auto start = std::chrono::high_resolution_clock::now();

    double sum = 0.0;
    // Simulate some scientific workload
    for (int i = 0; i < 5000; ++i) {
        for (int j = 0; j < 5000; ++j) {
            sum += std::sin(i) * std::cos(j);
        }
    }

    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double, std::milli> duration = end - start;

    // Output state
    std::cout << "State: " << std::fixed << std::setprecision(5) << sum << std::endl;
    std::cout << "Time: " << duration.count() << " ms" << std::endl;

    return 0;
}
EOF

    chmod -R 777 /home/user

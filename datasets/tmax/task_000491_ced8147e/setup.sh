#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generator.cpp
#include <iostream>
#include <random>
#include <string>

int main(int argc, char* argv[]) {
    if (argc != 2) return 1;
    int N = std::stoi(argv[1]);
    std::mt19937 gen(12345);
    // Using a distribution with variance = 2.0 (stddev approx 1.414)
    std::normal_distribution<double> dist(5.0, 1.41421356);

    for (int i = 0; i < N; ++i) {
        std::cout << dist(gen) << "\n";
    }
    return 0;
}
EOF

    chmod -R 777 /home/user

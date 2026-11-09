#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ espeak ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Generate the secret audio file
    espeak -w /app/secret_prior.wav "seventeen"

    # Write and compile the oracle
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <vector>
#include <cstdint>

int main() {
    std::vector<double> X;
    double val;
    while (std::cin >> val) {
        X.push_back(val);
    }

    if (X.empty()) {
        std::cout << 0 << std::endl;
        return 0;
    }

    int N = X.size();
    uint64_t seed = 12345;
    double M = 17.0; // Secret threshold from audio
    int count = 0;

    for (int r = 0; r < 10000; ++r) {
        double sum = 0.0;
        for (int i = 0; i < N; ++i) {
            seed = (1103515245 * seed + 12345) & 0x7FFFFFFF;
            int idx = seed % N;
            sum += X[idx];
        }
        double mean = sum / N;
        if (mean > M) {
            count++;
        }
    }

    std::cout << count << std::endl;
    return 0;
}
EOF

    g++ -O3 /app/oracle.cpp -o /app/oracle_mc_estimator
    rm /app/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 755 /app

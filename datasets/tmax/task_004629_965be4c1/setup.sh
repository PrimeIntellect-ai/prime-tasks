#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <string>
#include <cmath>
#include <random>
#include <iomanip>

int main(int argc, char* argv[]) {
    if (argc != 6) return 1;
    std::string seq = argv[1];
    double C00 = std::stod(argv[2]);
    double C01 = std::stod(argv[3]);
    double C10 = std::stod(argv[4]);
    double C11 = std::stod(argv[5]);

    int N = seq.length();
    double L00 = std::sqrt(C00);
    double L10 = C10 / L00;
    double L11 = std::sqrt(C11 - L10*L10);

    std::mt19937 gen(N);
    std::normal_distribution<double> dist(0.0, 1.0);

    double sum = 0.0;
    int M = 100000;
    for (int i = 0; i < M; ++i) {
        double max_x = -1e9;
        double min_y = 1e9;
        for (int j = 0; j < N; ++j) {
            double z0 = dist(gen);
            double z1 = dist(gen);
            double x = L00 * z0;
            double y = L10 * z0 + L11 * z1;
            if (x > max_x) max_x = x;
            if (y < min_y) min_y = y;
        }
        sum += (max_x - min_y);
    }
    std::cout << std::fixed << std::setprecision(4) << sum / M << std::endl;
    return 0;
}
EOF

    g++ -O3 -o /app/legacy_oracle /tmp/oracle.cpp
    strip /app/legacy_oracle
    rm /tmp/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

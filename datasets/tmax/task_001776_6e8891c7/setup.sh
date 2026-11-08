#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/spectra_gen.cpp
#include <iostream>
#include <cmath>
#include <cstdlib>
#include <iomanip>

int main(int argc, char* argv[]) {
    if(argc != 4) return 1;
    double a = std::atof(argv[1]);
    double mu = std::atof(argv[2]);
    double sigma = std::atof(argv[3]);

    for(int i=0; i<100; ++i) {
        double val = a * std::exp(-std::pow(i - mu, 2) / (2 * sigma * sigma));
        std::cout << std::fixed << std::setprecision(6) << val << (i == 99 ? "" : " ");
    }
    std::cout << std::endl;
    return 0;
}
EOF

    g++ -O3 -o /app/spectra_gen /app/spectra_gen.cpp
    strip /app/spectra_gen
    rm /app/spectra_gen.cpp
    chmod +x /app/spectra_gen

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

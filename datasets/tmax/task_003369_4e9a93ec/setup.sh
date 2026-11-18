#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/spectra_oracle.cpp
#include <iostream>
#include <cmath>
#include <cstdlib>

int main(int argc, char** argv) {
    if (argc != 4) return 1;
    double x = std::atof(argv[1]);
    double y = std::atof(argv[2]);
    double z = std::atof(argv[3]);
    for(int i=0; i<10; ++i) {
        double val = std::sin(x + i*0.5) * std::exp(-y/5.0) + z * (i / 10.0);
        std::cout << val << (i==9 ? "" : ",");
    }
    std::cout << std::endl;
    return 0;
}
EOF

    g++ -O3 /app/spectra_oracle.cpp -o /app/spectra_oracle
    strip /app/spectra_oracle
    rm /app/spectra_oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

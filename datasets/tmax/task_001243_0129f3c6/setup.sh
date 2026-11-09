#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/inv.cpp
#include <iostream>
#include <cstdlib>

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    double epsilon = std::atof(argv[1]);
    // Matrix A:
    // [ 1.0 , 1.0 ]
    // [ 1.0 , 1.0 + epsilon ]
    double a = 1.0, b = 1.0, c = 1.0, d = 1.0 + epsilon;
    double det = a*d - b*c;
    if (det == 0) {
        std::cout << "NaN" << std::endl;
        return 1;
    }
    double inv_a = d / det;
    std::cout << inv_a << std::endl;
    return 0;
}
EOF
    chmod 644 /home/user/inv.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

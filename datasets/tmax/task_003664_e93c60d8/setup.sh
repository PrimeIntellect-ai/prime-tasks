#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make libeigen3-dev binutils
    pip3 install pytest numpy

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

int main(int argc, char* argv[]) {
    if (argc != 2) return 1;
    std::ifstream file(argv[1]);
    std::string line;
    while (std::getline(file, line)) {
        std::stringstream ss(line);
        std::string cell;
        std::vector<double> x;
        while (std::getline(ss, cell, ',')) {
            x.push_back(std::stod(cell));
        }
        if (x.size() == 5) {
            double y = 2.5 * x[0] - 1.2 * x[1] + 3.1 * x[2] + 0.5 * x[3] - 0.8 * x[4] + 1.5;
            std::cout << y << std::endl;
        }
    }
    return 0;
}
EOF

    g++ -O3 /tmp/oracle.cpp -o /app/oracle
    strip -s /app/oracle
    rm /tmp/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

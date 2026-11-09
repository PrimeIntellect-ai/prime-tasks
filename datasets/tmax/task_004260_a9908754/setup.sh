#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install --no-cache-dir pytest numpy pandas flask

    mkdir -p /app/fastsim-2.0.0/src /app/fastsim-2.0.0/bin
    cat << 'EOF' > /app/fastsim-2.0.0/src/generator.cpp
#include <iostream>
#include <vector>
#include <cmath>
#include <iomanip>

int main(int argc, char** argv) {
    int n = 500;
    if (argc > 1) n = std::stoi(argv[1]);

    std::cout << "x,y\n";
    for(int i=0; i<n; ++i) {
        double x = i * 0.1;
        // Kahan summation to generate y
        double sum = 0.0;
        double c = 0.0;
        for(int j=1; j<=10000; ++j) {
            double y_val = (std::sin(x + j) / (j * j)) - c;
            double t = sum + y_val;
            c = (t - sum) - y_val;
            sum = t;
        }
        // Base linear relation + stable noise
        double y = 2.5 * x + 1.2 + sum;
        std::cout << std::fixed << std::setprecision(8) << x << "," << y << "\n";
    }
    return 0;
}
EOF

    cat << 'EOF' > /app/fastsim-2.0.0/Makefile
CXX=g++
CXXFLAGS=-O3 -ffast-math -std=c++17
all:
	$(CXX) $(CXXFLAGS) src/generator.cpp -o bin/generate_data
clean:
	rm -f bin/generate_data
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user

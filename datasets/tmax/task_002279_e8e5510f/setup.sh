#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/sim_project
    cd /home/user/sim_project

    cat << 'EOF' > simulator.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <cmath>
#include <iomanip>

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <input_file>\n";
        return 1;
    }

    std::ifstream infile(argv[1]);
    if (!infile) {
        std::cerr << "Failed to open input.\n";
        return 1;
    }

    std::string cmd;
    float current_pos = 0.0; // BUG: should be double
    bool failed = false;

    while (infile >> cmd) {
        if (cmd == "MOVE") {
            float v, dt; // BUG: should be double for precise accumulation
            int steps;
            infile >> v >> dt >> steps;
            for (int i = 0; i < steps; ++i) {
                current_pos += v * dt;
            }
        } else if (cmd == "CHECK") {
            double expected;
            infile >> expected;
            if (std::abs(current_pos - expected) > 1e-2) {
                std::cerr << "ERROR: mismatch! actual: " << std::setprecision(10) << current_pos 
                          << " expected: " << expected << "\n";
                failed = true;
            }
        }
    }

    if (!failed) {
        std::cout << "SUCCESS\n";
    }
    std::cout << "FINAL: " << std::setprecision(10) << current_pos << "\n";

    return failed ? 1 : 0;
}
EOF

    cat << 'EOF' > Makefile
simulator: simulator.cpp
	g++ -O3 -std=c++17 simulator.cpp -o simulator
EOF

    cat << 'EOF' > large_input.txt
MOVE 1.0000001 0.001 1000000
CHECK 1000.0001
MOVE 2.5000002 0.001 1000000
CHECK 3500.0003
MOVE -1.5000001 0.001 1000000
CHECK 2000.0002
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/sim_project
    chmod -R 777 /home/user

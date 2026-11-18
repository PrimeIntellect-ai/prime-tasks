#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy scipy pandas

    mkdir -p /home/user/src /home/user/bin /home/user/data

    cat << 'EOF' > /home/user/src/solver.cpp
#include <iostream>
#include <fstream>
#include <cmath>
#include <string>

int main() {
    std::string out_file = "/home/user/data/raw_peaks.csv";
    std::ofstream out(out_file);
    out << "intensity,frequency\n";
    int max_iter = 0;
    for(int i=1; i<=10; ++i) { // 10 peaks
        double M = i * 8.5;
        double E = M;
        double epsilon = 0.15;
        int iter = 0;
        while(true) {
            iter++;
            double E_next = M + epsilon * std::sin(E);
            if(std::abs(E_next - E) < 1e-7) break;
            E = E_next;
        }
        if(iter > max_iter) max_iter = iter;
        out << (100.0 / i) << "," << E << "\n";
    }
    out.close();
    std::cout << "Solver finished. Max convergence iterations: " << max_iter << std::endl;
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

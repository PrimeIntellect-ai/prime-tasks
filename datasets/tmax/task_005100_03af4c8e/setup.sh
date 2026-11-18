#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gdb strace
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/calc_engine.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>

int main() {
    std::ifstream infile("/home/user/input_batch.dat");
    if (!infile.is_open()) {
        std::cerr << "Failed to open input\n";
        return 1;
    }

    std::ofstream outfile("/home/user/output.txt");
    double x, y;
    int arr[100] = {0};

    while (infile >> x >> y) {
        double diff = x - y;
        double metric = 1.0 / diff; 

        // This will be massive or undefined if diff is 0, causing a segfault below
        int index = std::abs(static_cast<int>(metric));

        arr[index] = 1; // Crash here

        outfile << metric << "\n";
    }

    infile.close();
    outfile.close();
    return 0;
}
EOF

    cat << 'EOF' > /home/user/input_batch.dat
10.5 8.5
5.0 4.5
100.0 100.0
20.0 19.0
EOF

    chmod -R 777 /home/user

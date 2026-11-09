#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_data.py
import random

with open("queries.txt", "w") as f:
    for i in range(1, 5001):
        x = random.randint(10, 1000)
        y = random.randint(10, 1000)
        if i == 3412:
            x = -45  # The buggy input
        f.write(f"{i} {x} {y}\n")
EOF
    python3 generate_data.py
    rm generate_data.py

    cat << 'EOF' > process_queries.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>

// BUGGY FORMULA: Does not handle negative numbers properly, returning negative index
int compute_hash_index(int x) {
    return (x * 73) % 100;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <queries_file>" << std::endl;
        return 1;
    }

    std::ifstream in(argv[1]);
    int id, x, y;
    std::vector<int> lookup(100, 42); // Dummy lookup table of size 100

    while (in >> id >> x >> y) {
        int idx = compute_hash_index(x);

        // This will throw std::out_of_range if idx is negative
        int val = lookup.at(idx); 

        // Simulating some work
        if (val == -1) {
            std::cout << "Should not happen" << std::endl;
        }
    }

    std::cout << "Processing complete." << std::endl;
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

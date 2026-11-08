#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ valgrind
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_service.cpp
#include <iostream>
#include <string>
#include <vector>
#include <cmath>

void process_entry(const std::string& line) {
    // Allocate memory for processing cache
    std::vector<double>* data_cache = new std::vector<double>();

    double reading = 0.0;
    try {
        reading = std::stod(line);
    } catch (...) {
        // Corrupted input (e.g. unparseable string).
        std::cerr << "Error: Unparseable input." << std::endl;
        // MEMORY LEAK: data_cache is not deleted
        return;
    }

    // Floating point precision vulnerability:
    // If the reading is exactly 1.0 (or parsed as NaN/Inf), we hit an edge case.
    double divisor = reading - 1.0;
    double normalized = 10.0 / divisor;

    data_cache->push_back(normalized);

    if (std::isnan(normalized) || std::isinf(normalized)) {
        std::cerr << "Warning: Invalid normalized value." << std::endl;
        // MEMORY LEAK: data_cache is not deleted
        return;
    }

    std::cout << "Processed: " << normalized << std::endl;
    delete data_cache;
}

int main() {
    std::string line;
    while (std::getline(std::cin, line)) {
        process_entry(line);
    }
    return 0;
}
EOF

    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/etl

    cat << 'EOF' > /home/user/etl/data.csv
cat_A,9007199254740993
cat_B,9007199254740995
cat_A,
cat_B,2
cat_C,10000000000000000
cat_C,5
EOF

    cat << 'EOF' > /home/user/etl/aggregator.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <map>
#include <cstdint>

int main() {
    std::ifstream file("/home/user/etl/data.csv");
    std::map<std::string, uint64_t> sums;
    std::string line;

    while (std::getline(file, line)) {
        std::stringstream ss(line);
        std::string cat, val_str;
        std::getline(ss, cat, ',');
        std::getline(ss, val_str, ',');

        double val = 0.0;
        if (!val_str.empty()) {
            try {
                val = std::stod(val_str);
            } catch (...) {}
        }
        sums[cat] += static_cast<uint64_t>(val);
    }

    std::ofstream out("/home/user/etl/results.csv");
    for (const auto& pair : sums) {
        out << pair.first << "," << pair.second << "\n";
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

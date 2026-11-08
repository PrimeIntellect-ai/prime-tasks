#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/parser.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <iomanip>

double process_regular(const std::string& val_str) {
    return std::stod(val_str);
}

// LEGACY FUNCTION: Causing precision loss for FX_TRADE
float process_fx(const std::string& val_str) {
    // Format edge case: FX_TRADE sometimes has a '!' at the end of the amount string
    std::string clean_val = val_str;
    if (!clean_val.empty() && clean_val.back() == '!') {
        clean_val.pop_back();
    }
    return std::stof(clean_val);
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <filename>\n";
        return 1;
    }

    std::ifstream infile(argv[1]);
    if (!infile) {
        std::cerr << "Cannot open file\n";
        return 1;
    }

    std::string line;
    double total_sum = 0.0;

    while (std::getline(infile, line)) {
        if (line.empty()) continue;

        size_t comma_pos = line.find(',');
        if (comma_pos == std::string::npos) continue;

        std::string type = line.substr(0, comma_pos);
        std::string amount_str = line.substr(comma_pos + 1);

        if (type == "REGULAR") {
            total_sum += process_regular(amount_str);
        } else if (type == "FX_TRADE") {
            total_sum += process_fx(amount_str);
        }
    }

    std::cout << std::fixed << std::setprecision(4) << total_sum << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/generate_data.py
import random

with open("/home/user/transactions.txt", "w") as f:
    for i in range(5000):
        f.write("REGULAR,100.0001\n")
    f.write("FX_TRADE,12345678.1234!\n")
    for i in range(4999):
        f.write("REGULAR,100.0001\n")
EOF
    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    echo "13345578.2233" > /home/user/expected_sum.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

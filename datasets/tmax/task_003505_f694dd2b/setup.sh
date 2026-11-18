#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/aggregator.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <sstream>

int main() {
    std::ifstream file("/home/user/data.csv");
    if (!file.is_open()) return 1;

    std::string line;
    float total = 0.0f; // Precision loss bug

    // skip header
    std::getline(file, line);

    while (std::getline(file, line)) {
        std::stringstream ss(line);
        std::string item;
        std::vector<std::string> tokens;
        while (std::getline(ss, item, ',')) {
            tokens.push_back(item);
        }

        if (tokens.size() >= 3) {
            if (tokens[1] == "SALE") {
                // Bug: stoi/stof throws exception on empty/invalid string
                total += std::stof(tokens[2]); 
            }
        }
    }

    // Output total
    printf("%.2f\n", total);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/data.csv
ID,TYPE,AMOUNT
1,SALE,10000000.00
2,REFUND,-50.00
3,SALE,0.05
4,SALE,0.04
5,SALE,
6,SALE,15.00
EOF

    head -c 1024 /dev/urandom > /home/user/memdump.bin
    echo -n "ERR_CODE_9X2A_MALFORMED_CSV" >> /home/user/memdump.bin
    head -c 512 /dev/urandom >> /home/user/memdump.bin

    chmod 644 /home/user/aggregator.cpp /home/user/data.csv /home/user/memdump.bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

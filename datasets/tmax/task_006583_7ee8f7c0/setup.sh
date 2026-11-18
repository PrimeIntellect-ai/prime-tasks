#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/data_v1
    echo "sample_data" > /home/user/app/data_v1/input.txt

    cat << 'EOF' > /home/user/app/main.cpp
#include <iostream>
#include <fstream>
#include <string>

int main() {
    std::ifstream infile("/home/user/app/current_data/input.txt");
    if (!infile.is_open()) {
        std::cerr << "Fatal: Missing dependency. Cannot open /home/user/app/current_data/input.txt" << std::endl;
        return 1;
    }
    std::string data;
    infile >> data;

    std::ofstream outfile("/home/user/app/status.txt");
    if (outfile.is_open()) {
        outfile << "OK";
        outfile.close();
    }

    // Simulate daemon running
    return 0;
}
EOF

    g++ /home/user/app/main.cpp -o /home/user/app/processor

    chmod -R 777 /home/user

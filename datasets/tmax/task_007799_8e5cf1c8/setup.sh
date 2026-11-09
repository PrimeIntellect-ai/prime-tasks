#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/aggregator
    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/metrics.log
1700000000|app-container-1|OK|120
1700000005|app-container-2|OK|115
1700000010|db-container-1|OK|45
1700000015|cache-container-1|OK|12
1700000020|app-container-1|TIMEOUT|
1700000025|app-container-3|OK|130
1700000030|db-container-1|OK|40
1700000035|app-container-2|TIMEOUT|
1700000040|cache-container-1|OK|15
EOF

    cat << 'EOF' > /home/user/aggregator/aggregate.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <sstream>

int main() {
    std::ifstream file("/home/user/logs/metrics.log");
    if (!file.is_open()) {
        std::cerr << "Failed to open log file." << std::endl;
        return 1;
    }

    std::string line;
    long long total_latency = 0;
    int valid_counts = 0;

    while (std::getline(file, line)) {
        std::stringstream ss(line);
        std::string item;
        std::vector<std::string> tokens;

        while (std::getline(ss, item, '|')) {
            tokens.push_back(item);
        }

        // Bug: Doesn't check if tokens.size() is large enough or if status is not OK
        // If the line ends with a pipe like "|TIMEOUT|", the 4th token might not be generated or will be empty
        // std::stoi throws std::invalid_argument on empty string or out_of_range on vector
        int latency = std::stoi(tokens.at(3));

        total_latency += latency;
        valid_counts++;
    }

    if (valid_counts > 0) {
        std::cout << "Average Latency: " << total_latency / valid_counts << " ms" << std::endl;
    } else {
        std::cout << "No valid metrics found." << std::endl;
    }

    return 0;
}
EOF

    cd /home/user/aggregator
    g++ -O2 -o aggregate aggregate.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

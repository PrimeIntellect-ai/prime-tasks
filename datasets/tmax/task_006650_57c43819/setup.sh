#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/analytics.cpp
#include <iostream>
#include <iomanip>

int main() {
    double sum = 0;
    double sum_sq = 0;
    int count = 0;
    double val;

    while (std::cin >> val) {
        sum += val;
        sum_sq += (val * val);
        count++;
    }

    if (count <= 1) {
        std::cout << "0.000000" << std::endl;
        return 0;
    }

    // Naive variance formula - susceptible to catastrophic cancellation
    double variance = (sum_sq - ((sum * sum) / count)) / (count - 1);

    std::cout << std::fixed << std::setprecision(6) << variance << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/generate_data.py
import sys
with open("/home/user/query_results.txt", "w") as f:
    for i in range(1000):
        val = 100000000.0 + (i % 100) / 10.0
        f.write(f"{val}\n")
EOF
    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    chmod 644 /home/user/analytics.cpp
    chmod 644 /home/user/query_results.txt

    chmod -R 777 /home/user

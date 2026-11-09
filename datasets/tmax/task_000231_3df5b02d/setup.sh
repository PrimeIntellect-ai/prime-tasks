#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/analyzer.cpp
#include <iostream>
#include <vector>
#include <cmath>

double calculate_ema(const std::vector<double>& prices, double period) {
    if (prices.empty()) return 0.0;
    double k = 2.0 / (period + 1.0);
    double ema = prices[0];
    for (size_t i = 1; i < prices.size(); ++i) {
        // BUG: Multiplier should be (1.0 - k)
        ema = (prices[i] * k) + (ema * (1.0 + k));
    }
    return ema;
}

int main() {
    std::vector<double> p = {10.0, 11.0, 12.0};
    double res = calculate_ema(p, 2.0);
    std::cout << "EMA: " << res << std::endl;
    return 0;
}
EOF

    dd if=/dev/urandom of=/home/user/app/memory.bin bs=1K count=10 2>/dev/null
    echo -n "SOME_GARBAGE_TEST_KEY_849302_MORE_GARBAGE" >> /home/user/app/memory.bin
    dd if=/dev/urandom of=temp.bin bs=1K count=5 2>/dev/null
    cat temp.bin >> /home/user/app/memory.bin
    rm temp.bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

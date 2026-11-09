#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ upx-ucl curl netcat-openbsd strace gdb
pip3 install pytest

mkdir -p /app

cat << 'EOF' > /tmp/legacy_pricer.cpp
#include <iostream>
#include <cstdlib>
#include <iomanip>

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    long long N = std::atoll(argv[1]);
    double cost = 0.0;
    if (N < 1000) {
        cost = N * 0.05;
    } else {
        cost = 1000 * 0.05 + (N - 1000) * 0.02;
    }
    std::cout << std::fixed << std::setprecision(2) << cost << std::endl;
    return 0;
}
EOF

# Compile statically so the binary is large enough for UPX to compress
g++ -static -O2 -s /tmp/legacy_pricer.cpp -o /app/legacy_pricer
upx /app/legacy_pricer || true
chmod +x /app/legacy_pricer
rm /tmp/legacy_pricer.cpp

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app

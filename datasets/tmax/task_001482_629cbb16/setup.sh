#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gdb
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/utils.cpp
#include <string>

int extract_bytes(const std::string& line) {
    size_t pos = line.find_last_of(' ');
    if (pos != std::string::npos) {
        try {
            return std::stoi(line.substr(pos + 1));
        } catch (...) {
            return 0;
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/analyzer.cpp
#include <iostream>
#include <fstream>
#include <string>

// BUG 1: Mismatched signature causing linker error
int extract_bytes(std::string line);

int main() {
    std::ifstream infile("/home/user/system.log");
    if (!infile.is_open()) {
        std::cerr << "Failed to open log file" << std::endl;
        return 1;
    }
    std::string line;
    // BUG 2: 32-bit signed int overflow when accumulating large sums
    int total_bytes = 0;

    while (std::getline(infile, line)) {
        total_bytes += extract_bytes(line);
    }

    std::cout << total_bytes << std::endl;
    return 0;
}
EOF

    python3 -c "
log_path = '/home/user/system.log'
with open(log_path, 'w') as f:
    line = '192.168.1.1 - - [10/Oct/2000:13:55:36 -0700] \"GET /index.html HTTP/1.0\" 200 2000\n'
    for _ in range(1500000):
        f.write(line)
"

    chmod -R 777 /home/user

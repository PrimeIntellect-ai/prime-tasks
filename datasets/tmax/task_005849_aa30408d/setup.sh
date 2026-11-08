#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src

    cat << 'EOF' > /home/user/src/main.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <cstring>

const char* HIDDEN_TOKEN = "SECRET_TOKEN:a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4";

std::string process_line(const std::string& input) {
    char buffer[128];
    // VULNERABILITY: Buffer overflow if input > 127 chars
    strcpy(buffer, input.c_str());
    return std::string(buffer);
}

int main(int argc, char* argv[]) {
    if (argc != 3) {
        std::cerr << "Usage: " << argv[0] << " <input> <output>\n";
        return 1;
    }

    std::ifstream infile(argv[1]);
    std::ofstream outfile(argv[2]);

    if (!infile || !outfile) {
        std::cerr << "Error opening files.\n";
        return 1;
    }

    std::string line;
    while (std::getline(infile, line)) {
        outfile << process_line(line) << "\n";
    }

    return 0;
}
EOF

    g++ -O2 -std=c++11 /home/user/src/main.cpp -o /home/user/processor.elf

    cat << 'EOF' > /home/user/raw.log
INFO: User bob logged in.
DATA: SSN is 123-45-6789 and CC is 4111222233334444.
ERROR: Invalid transaction for 9876543210987654.
DATA: Contact at 555-12-3456 for details.
LONG: This is a very long line that would normally cause a buffer overflow because it exceeds the one hundred and twenty eight character limit that was hardcoded into the extremely poorly written legacy cpp application that we are testing right now.
EOF

    chmod -R 777 /home/user

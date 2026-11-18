#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user
    cat << 'EOF' > create_elf.cpp
#include <iostream>

// Encrypted version of "EVIDENCE_LOG: FLAG{3LF_4n4lys1s_X0R} END_LOG" with key 0x42
__attribute__((section(".maldata")))
const unsigned char encrypted_data[] = {
    0x07, 0x14, 0x0b, 0x06, 0x07, 0x0c, 0x01, 0x07, 0x1d, 0x0e, 0x0d, 0x05, 0x78, 0x62, 0x04, 0x0e,
    0x03, 0x05, 0x39, 0x71, 0x0e, 0x1d, 0x7f, 0x0c, 0x76, 0x0e, 0x3b, 0x31, 0x73, 0x1d, 0x7f, 0x1a,
    0x72, 0x10, 0x3f, 0x62, 0x07, 0x0c, 0x06, 0x1d, 0x0e, 0x0d, 0x05
};

int main() {
    std::cout << "Nothing to see here." << std::endl;
    return 0;
}
EOF

    g++ -o suspicious.elf create_elf.cpp
    rm create_elf.cpp

    chmod -R 777 /home/user

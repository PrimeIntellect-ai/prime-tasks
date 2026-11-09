#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ binutils gdb bsdmainutils
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cout << "INVALID: EMPTY_OR_UNREADABLE\n";
        return 1;
    }
    std::ifstream file(argv[1], std::ios::binary | std::ios::ate);
    if (!file) {
        std::cout << "INVALID: EMPTY_OR_UNREADABLE\n";
        return 1;
    }
    std::streamsize size = file.tellg();
    if (size == 0) {
        std::cout << "INVALID: EMPTY_OR_UNREADABLE\n";
        return 1;
    }
    if (size < 8) {
        std::cout << "INVALID: TOO_SHORT\n";
        return 1;
    }
    file.seekg(0, std::ios::beg);
    std::vector<char> buffer(size);
    if (!file.read(buffer.data(), size)) {
        std::cout << "INVALID: EMPTY_OR_UNREADABLE\n";
        return 1;
    }

    if (buffer[0] != 'M' || buffer[1] != 'L' || buffer[2] != 'S' || buffer[3] != 'T') {
        std::cout << "INVALID: BAD_MAGIC\n";
        return 1;
    }

    uint16_t version = static_cast<uint8_t>(buffer[4]) | (static_cast<uint8_t>(buffer[5]) << 8);
    if (version != 2) {
        std::cout << "INVALID: UNSUPPORTED_VERSION\n";
        return 1;
    }

    uint16_t expected_checksum = static_cast<uint8_t>(buffer[6]) | (static_cast<uint8_t>(buffer[7]) << 8);
    uint32_t sum = 0;
    for (std::streamsize i = 8; i < size; ++i) {
        sum += static_cast<uint8_t>(buffer[i]);
    }
    uint16_t calculated_checksum = sum % 65536;

    if (calculated_checksum != expected_checksum) {
        std::cout << "INVALID: CHECKSUM_MISMATCH\n";
        return 1;
    }

    std::cout << "VALID: CONFIG_OK\n";
    return 0;
}
EOF

g++ -O2 /app/oracle.cpp -o /app/mail_config_validator
strip -s /app/mail_config_validator
chmod 755 /app/mail_config_validator
rm /app/oracle.cpp

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

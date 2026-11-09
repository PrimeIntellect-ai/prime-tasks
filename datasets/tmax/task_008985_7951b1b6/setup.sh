#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make libssl-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/traffic_inspector

    cat << 'EOF' > /home/user/traffic_inspector/auth_logs.txt
192.168.1.10 | user1 | NORMAL_TOKEN_123 | 55a30f1465d6484e54e443f11e2f796a5bc8dcdd44ecb2c0cdb017b2f4f2c732
10.0.0.5 | admin | AUTH_EXPLOIT_PATTERN_X99_DROP | c4110de8dd7cb0372df3427382d610dc64e6211158b43bd7ba369905bfa802ea
172.16.0.4 | root | EXPLOIT_PATTERN_X99_BYPASS | aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
192.168.1.50 | user2 | VALID_EXPLOIT_PATTERN_X99_TEST | 374c43ceb439c0d54030d32bb3b6a95e79ff73587b13dd973d42e20b32cc629a
10.1.1.1 | test | REGULAR_AUTH_XYZ | 487dfb724fce109b0b1cc385ebc696e57ba51c2cfad42ecf2d4f2ccbbdd998e3
EOF

    cat << 'EOF' > /home/user/traffic_inspector/inspector.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <sstream>
// TODO: Include necessary OpenSSL headers

std.string compute_sha256(const std::string& input) {
    // TODO: Implement SHA-256 hashing using OpenSSL
    return "";
}

int main() {
    std::ifstream infile("auth_logs.txt");
    std::ofstream outfile("flagged_ips.log");
    std::string line;

    while (std::getline(infile, line)) {
        // TODO: Parse the pipe-separated line
        // TODO: Verify the hash
        // TODO: Check for EXPLOIT_PATTERN_X99
        // TODO: Write to flagged_ips.log if conditions are met
    }

    return 0;
}
EOF

    cat << 'EOF' > /home/user/traffic_inspector/Makefile
all:
	g++ -std=c++11 inspector.cpp -o inspector
EOF

    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libssl-dev binutils gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/vuln_scan

    cat << 'EOF' > /tmp/auth_checker.cpp
#include <iostream>
#include <string>
#include <openssl/sha.h>
#include <iomanip>

int main(int argc, char* argv[]) {
    if (argc != 2) return 1;
    std::string pin = argv[1];
    if (pin.length() != 4) return 1;
    std::string salt = "H4rdC0d3d_S@1t!";
    std::string input = salt + pin;

    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256_CTX sha256;
    SHA256_Init(&sha256);
    SHA256_Update(&sha256, input.c_str(), input.length());
    SHA256_Final(hash, &sha256);

    // Convert to hex (simulated check)
    std::string expected_hash = "some_target_hash";
    return 0; // Stub
}
EOF

    g++ -O3 /tmp/auth_checker.cpp -lcrypto -o /home/user/vuln_scan/auth_checker
    strip /home/user/vuln_scan/auth_checker
    rm /tmp/auth_checker.cpp

    for pin in "0451" "1337" "4920" "8080" "9999"; do
        echo -n "H4rdC0d3d_S@1t!$pin" | sha256sum | awk '{print $1}' >> /home/user/vuln_scan/hashes.txt
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc g++
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/bin
mkdir -p /home/user/.hidden_trust
mkdir -p /home/user/workspace

cat << 'EOF' > /home/user/workspace/legacy_monitor.c
#include <stdio.h>
int main() {
    printf("Loading CA from: /home/user/.hidden_trust/root_ca.crt\n");
    return 0;
}
EOF
gcc /home/user/workspace/legacy_monitor.c -o /home/user/bin/legacy_monitor

cat << 'EOF' > /home/user/jwt_auth.cpp
#include <iostream>
#include <string>

bool validate_algorithm(const std::string& header_json) {
    // VULNERABLE: accepts any algorithm, including none
    return true; 
}

int main(int argc, char** argv) {
    if(argc < 2) return 1;
    std::string header = argv[1]; // simplified: passing header json as arg
    if(validate_algorithm(header)) {
        std::cout << "VALID" << std::endl;
        return 0;
    } else {
        std::cout << "INVALID" << std::endl;
        return 1;
    }
}
EOF

chmod -R 777 /home/user
chmod 4755 /home/user/bin/legacy_monitor

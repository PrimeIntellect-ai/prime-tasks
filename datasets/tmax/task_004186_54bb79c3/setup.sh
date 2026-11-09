#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libssl-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/vault.txt
Tr0ub4dour&3
EOF

    cat << 'EOF' > /home/user/auth_service.cpp
#include <iostream>
#include <fstream>

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    std::string password = argv[1];
    // Vulnerable: password in argv
    std::cout << "Authenticating with " << password << std::endl;
    return 0;
}
EOF

    chmod -R 777 /home/user
    chmod 0644 /home/user/vault.txt

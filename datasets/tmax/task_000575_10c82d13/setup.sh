#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ openssl bubblewrap
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server.cpp
#include <iostream>
#include <string>

bool validate_token(const std::string& token) {
    if (token.find("|sig:none") != std::string::npos) {
        return true; // VULNERABILITY: bypasses actual signature check
    }
    if (token.find("|sig:VALID_MAC") != std::string::npos) {
        return true;
    }
    return false;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        return 1;
    }
    std::string token = argv[1];
    if (validate_token(token)) {
        std::cout << "Authenticated\n";
        return 0;
    } else {
        std::cout << "Denied\n";
        return 1;
    }
}
EOF

    mkdir -p /home/user/test_env
    touch /home/user/test_env/normal_bin
    touch /home/user/test_env/fake_sudo

    chmod -R 777 /home/user
    chmod 755 /home/user/test_env/normal_bin
    chmod 4755 /home/user/test_env/fake_sudo

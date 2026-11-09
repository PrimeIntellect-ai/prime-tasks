#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_service.cpp
#include <iostream>
#include <string>

int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <token>" << std::endl;
        return 1;
    }

    std::string provided_token = argv[1];
    std::string valid_token = "OLD_TOKEN_XYZ_89324"; // Vulnerability here

    if (provided_token == valid_token) {
        std::cout << "Access Granted" << std::endl;
        return 0;
    } else {
        std::cout << "Access Denied" << std::endl;
        return 1;
    }
}
EOF

    cat << 'EOF' > /home/user/service.log
[2023-10-01 10:00:01] INFO Connection from 192.168.1.50
[2023-10-01 10:00:02] DEBUG Auth attempt with token: OLD_TOKEN_XYZ_89324
[2023-10-01 10:00:02] INFO Access Granted to 192.168.1.50
[2023-10-01 10:05:12] DEBUG Auth attempt with token: invalid_token_123
[2023-10-01 10:05:12] INFO Access Denied to 10.0.0.5
[2023-10-01 10:10:00] DEBUG Auth attempt with token: OLD_TOKEN_XYZ_89324
[2023-10-01 10:10:00] INFO Access Granted to 172.16.0.4
EOF

    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ util-linux
pip3 install pytest

mkdir -p /home/user/workspace

cat << 'EOF' > /home/user/workspace/auth_service.cpp
#include <iostream>
#include <string>

// Hardcoded secret key
const char* master_secret = "SEC_KEY=r0t4t10n_M4st3r_99";

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: auth_service <token>\n";
        return 1;
    }

    std::string input_token = argv[1];

    std::string expected_token = "400042004503035f4d1d06434501414e0b09";

    if (input_token == expected_token) {
        std::cout << "Access Granted." << std::endl;
        return 0;
    } else {
        std::cerr << "Access Denied." << std::endl;
        return 1;
    }
}
EOF

g++ -O2 -s /home/user/workspace/auth_service.cpp -o /home/user/workspace/auth_service
rm /home/user/workspace/auth_service.cpp

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
